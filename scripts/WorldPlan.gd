class_name WorldPlan
extends RefCounted

## ===========================================================================
## THE WORLD PLAN — scripts/WorldPlan.gd
##
## The design layer of the map: what goes WHERE, and what Lemon wants done
## about it. Nothing here renders, moves or collides. It is a pile of records
## on disk that the god-mode editor (scripts/GodEditor.gd) writes and that
## Claude reads next session.
##
## Three record types:
##
##   ZONE  an area on the ground — a village, a farm, a forest, a city.
##         A polygon (or a circle, which is a polygon with a radius it
##         remembers). Carries a kind, a name, a status and its notes.
##
##   PATH  a line on the ground — a road, a cart track, a footpath, a wall,
##         a bridge. A polyline with a width.
##
##   NOTE  a pin at a point, optionally attached to a zone or a path.
##         Title + body + tag. THIS is the "leave Claude a note" system:
##         a note filed under a zone is a note about that zone, and the
##         Markdown export groups them that way — the sectioning.
##
## ON DISK (two files, same data, two audiences):
##
##   design/world_plan.json   the truth. Read and written by the editor.
##   design/WORLD_PLAN.md     the same thing as prose, grouped zone by zone,
##                            with coordinates and checkboxes. Regenerated on
##                            every save. This is the file Claude reads.
##
## Written into res://design/ when that is writable (running from the Godot
## editor, which is the only way anyone is using god mode) and into
## user://design/ otherwise. `WorldPlan.dir()` says which won.
##
## LATER (the Stardew build system): zones are the natural home for buildable
## land. A "farm" zone with status "done" is a plot; BuildKit costs plus a
## zone test is most of a placement rule. Nothing here assumes an editor.
## ===========================================================================

const FILE_JSON := "world_plan.json"
const FILE_MD := "WORLD_PLAN.md"
const FORMAT := 1

## --- what an area can BE --------------------------------------------------
## id -> {label, color, cat}.  cat groups the buttons in the editor panel.
const ZONE_KINDS := {
	"city":        {"label": "City",          "color": Color(0.92, 0.36, 0.28), "cat": "Settlement"},
	"town":        {"label": "Town",          "color": Color(0.94, 0.55, 0.30), "cat": "Settlement"},
	"village":     {"label": "Village",       "color": Color(0.96, 0.74, 0.36), "cat": "Settlement"},
	"hamlet":      {"label": "Hamlet",        "color": Color(0.88, 0.82, 0.52), "cat": "Settlement"},
	"camp":        {"label": "Camp",          "color": Color(0.80, 0.66, 0.44), "cat": "Settlement"},
	"docks":       {"label": "Docks",         "color": Color(0.55, 0.72, 0.86), "cat": "Settlement"},
	"market":      {"label": "Market",        "color": Color(0.95, 0.62, 0.62), "cat": "Settlement"},

	"farm":        {"label": "Farm",          "color": Color(0.86, 0.78, 0.30), "cat": "Worked land"},
	"orchard":     {"label": "Orchard",       "color": Color(0.72, 0.80, 0.34), "cat": "Worked land"},
	"pasture":     {"label": "Pasture",       "color": Color(0.62, 0.82, 0.46), "cat": "Worked land"},
	"logging":     {"label": "Logging camp",  "color": Color(0.68, 0.52, 0.32), "cat": "Worked land"},
	"quarry":      {"label": "Quarry",        "color": Color(0.66, 0.66, 0.70), "cat": "Worked land"},
	"mine":        {"label": "Mine",          "color": Color(0.50, 0.50, 0.58), "cat": "Worked land"},
	"mill":        {"label": "Mill",          "color": Color(0.76, 0.64, 0.44), "cat": "Worked land"},

	"forest":      {"label": "Forest",        "color": Color(0.22, 0.58, 0.30), "cat": "Wild"},
	"oldgrowth":   {"label": "Old growth",    "color": Color(0.12, 0.42, 0.22), "cat": "Wild"},
	"plains":      {"label": "Plains",        "color": Color(0.72, 0.86, 0.48), "cat": "Wild"},
	"meadow":      {"label": "Meadow",        "color": Color(0.80, 0.90, 0.52), "cat": "Wild"},
	"moor":        {"label": "Moor",          "color": Color(0.64, 0.60, 0.42), "cat": "Wild"},
	"marsh":       {"label": "Marsh",         "color": Color(0.44, 0.62, 0.48), "cat": "Wild"},
	"beach":       {"label": "Beach",         "color": Color(0.92, 0.88, 0.66), "cat": "Wild"},
	"highland":    {"label": "Highland",      "color": Color(0.70, 0.74, 0.80), "cat": "Wild"},

	"keep":        {"label": "Keep / castle", "color": Color(0.62, 0.56, 0.76), "cat": "Story"},
	"ruin":        {"label": "Ruin",          "color": Color(0.58, 0.52, 0.50), "cat": "Story"},
	"shrine":      {"label": "Shrine",        "color": Color(0.84, 0.72, 0.94), "cat": "Story"},
	"graveyard":   {"label": "Graveyard",     "color": Color(0.50, 0.50, 0.60), "cat": "Story"},
	"dungeon":     {"label": "Dungeon",       "color": Color(0.44, 0.30, 0.46), "cat": "Story"},
	"cave_mouth":  {"label": "Cave mouth",    "color": Color(0.34, 0.30, 0.34), "cat": "Story"},
	"arena":       {"label": "Boss arena",    "color": Color(0.86, 0.24, 0.44), "cat": "Story"},
	"bandit":      {"label": "Bandit camp",   "color": Color(0.72, 0.30, 0.26), "cat": "Story"},

	"spawn":       {"label": "Spawn",         "color": Color(0.40, 0.90, 0.90), "cat": "Meta"},
	"poi":         {"label": "Point of int.", "color": Color(0.90, 0.90, 0.40), "cat": "Meta"},
	"keepout":     {"label": "Keep clear",    "color": Color(0.90, 0.25, 0.25), "cat": "Meta"},
	"todo":        {"label": "Needs work",    "color": Color(1.00, 0.45, 0.10), "cat": "Meta"},
}

## --- what a line can BE ---------------------------------------------------
const PATH_KINDS := {
	"kingsroad":  {"label": "King's road", "color": Color(0.90, 0.80, 0.56), "width": 9.0},
	"road":       {"label": "Road",        "color": Color(0.82, 0.72, 0.50), "width": 6.0},
	"cart":       {"label": "Cart track",  "color": Color(0.70, 0.60, 0.42), "width": 3.6},
	"trail":      {"label": "Trail",       "color": Color(0.62, 0.56, 0.40), "width": 1.8},
	"game_trail": {"label": "Game trail",  "color": Color(0.52, 0.58, 0.38), "width": 1.0},
	"bridge":     {"label": "Bridge",      "color": Color(0.72, 0.52, 0.34), "width": 5.0},
	"ford":       {"label": "Ford",        "color": Color(0.50, 0.72, 0.84), "width": 6.0},
	"wall":       {"label": "Wall",        "color": Color(0.66, 0.64, 0.64), "width": 2.0},
	"palisade":   {"label": "Palisade",    "color": Color(0.60, 0.46, 0.32), "width": 1.4},
	"fenceline":  {"label": "Fence line",  "color": Color(0.74, 0.66, 0.48), "width": 0.8},
	"canal":      {"label": "Canal",       "color": Color(0.42, 0.66, 0.80), "width": 7.0},
}

const NOTE_TAGS := ["todo", "idea", "question", "bug", "lore", "done"]
const NOTE_TAG_COLOR := {
	"todo":     Color(1.00, 0.62, 0.20),
	"idea":     Color(0.55, 0.86, 1.00),
	"question": Color(0.86, 0.70, 1.00),
	"bug":      Color(1.00, 0.35, 0.35),
	"lore":     Color(0.70, 0.90, 0.60),
	"done":     Color(0.55, 0.60, 0.55),
}

const STATUSES := ["idea", "planned", "building", "done"]
const PRIORITIES := ["low", "normal", "high", "next"]

# ===========================================================================
#  State
# ===========================================================================

static var zones: Array = []
static var paths: Array = []
static var notes: Array = []
static var loaded := false
static var last_error := ""
static var _next_id := 1
static var _dir := ""


static func dir() -> String:
	## Where the plan lives. res:// when we can write there (the Godot editor),
	## user:// otherwise. Resolved once, on the first call.
	if _dir != "":
		return _dir
	if DirAccess.make_dir_recursive_absolute("res://design") == OK:
		var probe := FileAccess.open("res://design/.writable", FileAccess.WRITE)
		if probe != null:
			probe.store_string("ok")
			probe.close()
			DirAccess.remove_absolute("res://design/.writable")
			_dir = "res://design/"
			return _dir
	DirAccess.make_dir_recursive_absolute("user://design")
	_dir = "user://design/"
	return _dir


static func json_path() -> String:
	return dir() + FILE_JSON


static func md_path() -> String:
	return dir() + FILE_MD


# ===========================================================================
#  Load / save
# ===========================================================================

static func load_plan() -> void:
	zones = []
	paths = []
	notes = []
	_next_id = 1
	loaded = true
	last_error = ""
	var p := json_path()
	if not FileAccess.file_exists(p):
		return
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		last_error = "could not open %s" % p
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		last_error = "%s is not a JSON object" % p
		return
	var d: Dictionary = parsed
	zones = (d.get("zones", []) as Array).duplicate(true)
	paths = (d.get("paths", []) as Array).duplicate(true)
	notes = (d.get("notes", []) as Array).duplicate(true)
	_next_id = int(d.get("next_id", 1))
	## Never trust the counter over the records themselves.
	for coll in [zones, paths, notes]:
		for r in coll:
			var n := _id_number(str((r as Dictionary).get("id", "")))
			if n >= _next_id:
				_next_id = n + 1


static func save_plan() -> bool:
	last_error = ""
	var d := {
		"format": FORMAT,
		"saved": Time.get_datetime_string_from_system(),
		"next_id": _next_id,
		"zones": zones,
		"paths": paths,
		"notes": notes,
	}
	var f := FileAccess.open(json_path(), FileAccess.WRITE)
	if f == null:
		last_error = "could not write %s" % json_path()
		push_warning("WorldPlan: " + last_error)
		return false
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	_write_markdown()
	return true


static func _id_number(id: String) -> int:
	var bits := id.split("_")
	if bits.size() < 2:
		return 0
	return int(bits[bits.size() - 1])


static func _new_id(prefix: String) -> String:
	var id := "%s_%04d" % [prefix, _next_id]
	_next_id += 1
	return id


static func _now() -> String:
	return Time.get_datetime_string_from_system(false, true)


# ===========================================================================
#  Making things
# ===========================================================================

static func new_zone(kind: String, pts: PackedVector2Array, shape := "poly",
		radius := 0.0) -> Dictionary:
	var z := {
		"id": _new_id("zone"),
		"kind": kind,
		"name": _auto_name(kind),
		"shape": shape,
		"points": _pack_points(pts),
		"radius": radius,
		"center": _pack_point(_centroid_of(pts)),
		"status": "planned",
		"priority": "normal",
		"created": _now(),
	}
	zones.append(z)
	return z


static func new_path(kind: String, pts: PackedVector2Array, width := -1.0) -> Dictionary:
	var w := width
	if w <= 0.0:
		w = float((PATH_KINDS.get(kind, {"width": 4.0}) as Dictionary).get("width", 4.0))
	var p := {
		"id": _new_id("path"),
		"kind": kind,
		"name": _auto_name(kind),
		"points": _pack_points(pts),
		"width": w,
		"status": "planned",
		"priority": "normal",
		"created": _now(),
	}
	paths.append(p)
	return p


static func new_note(pos: Vector3, title: String, body: String, tag := "todo",
		owner_id := "") -> Dictionary:
	var n := {
		"id": _new_id("note"),
		"owner": owner_id,
		"pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(pos.z, 0.1)],
		"tag": tag,
		"title": title,
		"body": body,
		"created": _now(),
	}
	notes.append(n)
	return n


static func _auto_name(kind: String) -> String:
	var label := kind.capitalize()
	if ZONE_KINDS.has(kind):
		label = str((ZONE_KINDS[kind] as Dictionary)["label"])
	elif PATH_KINDS.has(kind):
		label = str((PATH_KINDS[kind] as Dictionary)["label"])
	var n := 1
	for coll in [zones, paths]:
		for r in coll:
			if str((r as Dictionary).get("kind", "")) == kind:
				n += 1
	return "%s %d" % [label, n]


static func remove(id: String) -> bool:
	for coll in [zones, paths]:
		for i in range(coll.size()):
			if str((coll[i] as Dictionary).get("id", "")) == id:
				coll.remove_at(i)
				## its notes come off with it — they described a thing
				## that no longer exists.
				var keep: Array = []
				for n in notes:
					if str((n as Dictionary).get("owner", "")) != id:
						keep.append(n)
				notes = keep
				return true
	for i in range(notes.size()):
		if str((notes[i] as Dictionary).get("id", "")) == id:
			notes.remove_at(i)
			return true
	return false


static func find(id: String) -> Dictionary:
	for coll in [zones, paths, notes]:
		for r in coll:
			if str((r as Dictionary).get("id", "")) == id:
				return r
	return {}


static func notes_for(id: String) -> Array:
	var out: Array = []
	for n in notes:
		if str((n as Dictionary).get("owner", "")) == id:
			out.append(n)
	return out


static func loose_notes() -> Array:
	var out: Array = []
	for n in notes:
		var o := str((n as Dictionary).get("owner", ""))
		if o == "" or find(o).is_empty():
			out.append(n)
	return out


# ===========================================================================
#  Geometry
# ===========================================================================

static func _pack_point(v: Vector2) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]


static func _pack_points(pts: PackedVector2Array) -> Array:
	var out: Array = []
	for v in pts:
		out.append(_pack_point(v))
	return out


static func points_of(rec: Dictionary) -> PackedVector2Array:
	## The polygon (or polyline) of a record in world XZ metres. A circle zone
	## is generated from its centre and radius, so resizing one is one number.
	if str(rec.get("shape", "poly")) == "circle":
		var c := center_of(rec)
		var r := float(rec.get("radius", 10.0))
		var out := PackedVector2Array()
		for i in range(CIRCLE_SEGS):
			var a := TAU * float(i) / float(CIRCLE_SEGS)
			out.append(c + Vector2(cos(a), sin(a)) * r)
		return out
	var pts := PackedVector2Array()
	for p in (rec.get("points", []) as Array):
		var a: Array = p
		pts.append(Vector2(float(a[0]), float(a[1])))
	return pts


const CIRCLE_SEGS := 28


static func center_of(rec: Dictionary) -> Vector2:
	var c: Array = rec.get("center", [])
	if c.size() == 2:
		return Vector2(float(c[0]), float(c[1]))
	return _centroid_of(points_of(rec))


static func _centroid_of(pts: PackedVector2Array) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var s := Vector2.ZERO
	for v in pts:
		s += v
	return s / float(pts.size())


static func recenter(rec: Dictionary) -> void:
	if str(rec.get("shape", "poly")) != "circle":
		rec["center"] = _pack_point(_centroid_of(points_of(rec)))


static func area_of(rec: Dictionary) -> float:
	## Shoelace, square metres.
	var pts := points_of(rec)
	if pts.size() < 3:
		return 0.0
	var a := 0.0
	for i in range(pts.size()):
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


static func length_of(rec: Dictionary) -> float:
	var pts := points_of(rec)
	var l := 0.0
	for i in range(pts.size() - 1):
		l += pts[i].distance_to(pts[i + 1])
	return l


static func bbox_of(rec: Dictionary) -> Rect2:
	var pts := points_of(rec)
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for v in pts:
		r = r.expand(v)
	return r


static func contains(rec: Dictionary, wx: float, wz: float) -> bool:
	if str(rec.get("shape", "poly")) == "circle":
		return center_of(rec).distance_to(Vector2(wx, wz)) <= float(rec.get("radius", 0.0))
	var pts := points_of(rec)
	if pts.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(Vector2(wx, wz), pts)


static func zone_at(wx: float, wz: float) -> Dictionary:
	## The SMALLEST zone containing the point — a market square inside a city
	## should win over the city.
	var best := {}
	var best_a := INF
	for z in zones:
		var zd: Dictionary = z
		if contains(zd, wx, wz):
			var a := area_of(zd)
			if a < best_a:
				best_a = a
				best = zd
	return best


static func kind_color(rec: Dictionary) -> Color:
	var k := str(rec.get("kind", ""))
	if ZONE_KINDS.has(k):
		return (ZONE_KINDS[k] as Dictionary)["color"]
	if PATH_KINDS.has(k):
		return (PATH_KINDS[k] as Dictionary)["color"]
	return Color(0.8, 0.8, 0.8)


static func kind_label(rec: Dictionary) -> String:
	var k := str(rec.get("kind", ""))
	if ZONE_KINDS.has(k):
		return str((ZONE_KINDS[k] as Dictionary)["label"])
	if PATH_KINDS.has(k):
		return str((PATH_KINDS[k] as Dictionary)["label"])
	return k.capitalize()


# ===========================================================================
#  The Markdown export — the file Claude actually reads
# ===========================================================================

static func _write_markdown() -> void:
	var f := FileAccess.open(md_path(), FileAccess.WRITE)
	if f == null:
		push_warning("WorldPlan: could not write %s" % md_path())
		return
	f.store_string(markdown())
	f.close()


static func markdown() -> String:
	var out := PackedStringArray()
	out.append("# Myrkfell — world plan")
	out.append("")
	out.append("> Written by the in-game god editor (`scripts/GodEditor.gd`) on %s."
		% Time.get_datetime_string_from_system())
	out.append("> Data: `%s`. Edit the world in game, not this file — it is regenerated on every save."
		% json_path())
	out.append("")
	out.append("Coordinates are world metres: **+x east, +z south**, y up. Sea level is y −22.5,")
	out.append("the spawn valley is the origin. `Overworld.ground_y(pos)` is the surface.")
	out.append("")

	## --- the standing orders, first, because they are the point ------------
	var open_notes := _open_notes()
	out.append("## Open notes (%d)" % open_notes.size())
	out.append("")
	if open_notes.is_empty():
		out.append("_Nothing outstanding._")
	else:
		for n in open_notes:
			var nd: Dictionary = n
			out.append("- %s" % _note_line(nd, true))
	out.append("")

	## --- zones, grouped by category then kind ------------------------------
	out.append("## Zones (%d)" % zones.size())
	out.append("")
	if zones.is_empty():
		out.append("_None drawn yet._")
		out.append("")
	var cats := _zone_categories()
	for cat in cats:
		var members: Array = cats[cat]
		out.append("### %s" % cat)
		out.append("")
		for z in members:
			_zone_section(out, z as Dictionary)
	## --- paths --------------------------------------------------------------
	out.append("## Roads, trails and lines (%d)" % paths.size())
	out.append("")
	if paths.is_empty():
		out.append("_None drawn yet._")
		out.append("")
	for p in paths:
		_path_section(out, p as Dictionary)

	## --- notes with no home -------------------------------------------------
	var loose := loose_notes()
	if not loose.is_empty():
		out.append("## Loose notes (%d)" % loose.size())
		out.append("")
		out.append("Pins dropped outside any zone or path.")
		out.append("")
		for n in loose:
			out.append("- %s" % _note_line(n as Dictionary, true))
		out.append("")

	out.append("---")
	out.append("")
	out.append("### Legend")
	out.append("")
	out.append("`[ ]` open · `[x]` done · **status** idea → planned → building → done ·")
	out.append("**priority** low / normal / high / next.")
	out.append("Tags: `todo` `idea` `question` `bug` `lore` `done`.")
	out.append("")
	return "\n".join(out) + "\n"


static func _zone_categories() -> Dictionary:
	var order: Array[String] = ["Settlement", "Worked land", "Wild", "Story", "Meta", "Other"]
	var out := {}
	for c in order:
		out[c] = []
	for z in zones:
		var k := str((z as Dictionary).get("kind", ""))
		var cat := "Other"
		if ZONE_KINDS.has(k):
			cat = str((ZONE_KINDS[k] as Dictionary).get("cat", "Other"))
		(out[cat] as Array).append(z)
	for c in order:
		if (out[c] as Array).is_empty():
			out.erase(c)
	return out


static func _zone_section(out: PackedStringArray, z: Dictionary) -> void:
	var c := center_of(z)
	var bb := bbox_of(z)
	var a := area_of(z)
	out.append("#### %s — %s" % [str(z.get("name", "?")), kind_label(z)])
	out.append("")
	out.append("- `%s` · **%s** · priority **%s**"
		% [str(z.get("id", "")), str(z.get("status", "planned")), str(z.get("priority", "normal"))])
	out.append("- centre `(%.0f, %.0f)` · ground y %.1f · %s"
		% [c.x, c.y, _ground(c), _where(c)])
	if str(z.get("shape", "poly")) == "circle":
		out.append("- circle, radius %.0f m · area %s" % [float(z.get("radius", 0.0)), _area_str(a)])
	else:
		out.append("- %d-point polygon · %.0f × %.0f m box · area %s"
			% [points_of(z).size(), bb.size.x, bb.size.y, _area_str(a)])
	out.append("- extent x `%.0f … %.0f`, z `%.0f … %.0f`"
		% [bb.position.x, bb.end.x, bb.position.y, bb.end.y])
	var mine := notes_for(str(z.get("id", "")))
	if mine.is_empty():
		out.append("- _no notes_")
	else:
		out.append("")
		for n in mine:
			out.append("  - %s" % _note_line(n as Dictionary, false))
	out.append("")


static func _path_section(out: PackedStringArray, p: Dictionary) -> void:
	var pts := points_of(p)
	out.append("### %s — %s" % [str(p.get("name", "?")), kind_label(p)])
	out.append("")
	out.append("- `%s` · **%s** · priority **%s** · width %.1f m · length %.0f m"
		% [str(p.get("id", "")), str(p.get("status", "planned")),
		   str(p.get("priority", "normal")), float(p.get("width", 4.0)),
		   length_of(p)])
	if pts.size() >= 2:
		out.append("- from `(%.0f, %.0f)` %s" % [pts[0].x, pts[0].y, _where(pts[0])])
		out.append("- to `(%.0f, %.0f)` %s"
			% [pts[pts.size() - 1].x, pts[pts.size() - 1].y, _where(pts[pts.size() - 1])])
		var wp := PackedStringArray()
		for v in pts:
			wp.append("(%.0f, %.0f)" % [v.x, v.y])
		out.append("- waypoints: %s" % ", ".join(wp))
	var mine := notes_for(str(p.get("id", "")))
	if not mine.is_empty():
		out.append("")
		for n in mine:
			out.append("  - %s" % _note_line(n as Dictionary, false))
	out.append("")


static func _note_line(n: Dictionary, with_place: bool) -> String:
	var tag := str(n.get("tag", "todo"))
	var box := "[x]" if tag == "done" else "[ ]"
	var title := str(n.get("title", "")).strip_edges()
	if title == "":
		title = "(untitled)"
	var s := "%s **%s** `%s`" % [box, title, tag]
	var owner_id := str(n.get("owner", ""))
	if with_place and owner_id != "":
		var o := find(owner_id)
		if not o.is_empty():
			s += " — in _%s_" % str(o.get("name", owner_id))
	var pa: Array = n.get("pos", [0, 0, 0])
	s += " · `(%.0f, %.0f, %.0f)`" % [float(pa[0]), float(pa[1]), float(pa[2])]
	if with_place:
		s += " %s" % _where(Vector2(float(pa[0]), float(pa[2])))
	var body := str(n.get("body", "")).strip_edges()
	if body != "":
		s += "\n\n    " + body.replace("\n", "\n    ")
	return s


static func _open_notes() -> Array:
	var out: Array = []
	for n in notes:
		if str((n as Dictionary).get("tag", "todo")) != "done":
			out.append(n)
	## `next`/`high` priority owners float their notes to the top.
	out.sort_custom(func(a, b):
		return _note_rank(a as Dictionary) < _note_rank(b as Dictionary))
	return out


static func _note_rank(n: Dictionary) -> int:
	var owner_id := str(n.get("owner", ""))
	var pr := "normal"
	if owner_id != "":
		var o := find(owner_id)
		if not o.is_empty():
			pr = str(o.get("priority", "normal"))
	var by_pri := {"next": 0, "high": 1, "normal": 2, "low": 3}
	var by_tag := {"bug": 0, "todo": 1, "question": 2, "idea": 3, "lore": 4, "done": 5}
	return int(by_pri.get(pr, 2)) * 10 + int(by_tag.get(str(n.get("tag", "todo")), 3))


static func _area_str(a: float) -> String:
	if a >= 1000000.0:
		return "%.2f km²" % (a / 1000000.0)
	if a >= 10000.0:
		return "%.1f ha" % (a / 10000.0)
	return "%.0f m²" % a


static func _ground(c: Vector2) -> float:
	return Overworld.ground_y(Vector3(c.x, 0.0, c.y))


static func _where(c: Vector2) -> String:
	## Human bearings: the nearest named place and the region, so a coordinate
	## in the Markdown means something without opening the game.
	if Overworld.inst == null:
		return ""
	var p := Vector3(c.x, 0.0, c.y)
	var place := Overworld.inst.place_name_at(p, 2500.0)
	var region := Overworld.inst.region_for(c.x, c.y)
	if place != "":
		return "· near **%s** (%s)" % [place, region]
	return "· %s" % region
