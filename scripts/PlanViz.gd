class_name PlanViz
extends Node3D

## ===========================================================================
## THE PLAN, DRAWN — scripts/PlanViz.gd
##
## Turns WorldPlan's records into something you can stand next to: a coloured
## curtain around every zone, a ribbon down every road, a lit pin on every
## note. Everything is unshaded, translucent and drawn WITHOUT depth test, so
## the plan reads through hills and trees — you can see the village boundary
## from the ridge above it, which is the whole point.
##
## Owns no data. `rebuild()` throws the lot away and re-reads WorldPlan.
## Hidden whenever the god editor is closed unless you pin it on.
## ===========================================================================

const WALL_H := 3.2           ## how tall the boundary curtain stands
const STEP := 4.0             ## metres between terrain samples along an edge
const FILL_LIFT := 0.30       ## the ground fill floats this far off the dirt
const LABEL_LIFT := 9.0       ## the name floats this far over the centre
const PIN_H := 2.6            ## note pin height

var show_fill := true
var show_walls := true
var show_labels := true

var _root: Node3D
var _mat_cache := {}


func _ready() -> void:
	add_to_group("plan_viz")
	_ensure_root()


func _ensure_root() -> void:
	## rebuild() can be called the same frame the node is added, before _ready
	## has run in some orders -- build the holder on demand rather than trusting
	## the callback to have happened.
	if _root != null and is_instance_valid(_root):
		return
	_root = Node3D.new()
	_root.name = "PlanDraw"
	add_child(_root)


# ===========================================================================
#  Materials
# ===========================================================================

func _mat(col: Color, alpha: float, unlit := true) -> StandardMaterial3D:
	var key := "%s_%.2f_%s" % [col.to_html(false), alpha, str(unlit)]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unlit \
		else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 2
	m.disable_receive_shadows = true
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.6
	_mat_cache[key] = m
	return m


# ===========================================================================
#  Rebuild
# ===========================================================================

func rebuild() -> void:
	_ensure_root()
	for c in _root.get_children():
		c.queue_free()
	for z in WorldPlan.zones:
		_draw_zone(z as Dictionary)
	for p in WorldPlan.paths:
		_draw_path(p as Dictionary)
	for n in WorldPlan.notes:
		_draw_note(n as Dictionary)


func _g(x: float, z: float) -> float:
	return Overworld.ground_y(Vector3(x, 0.0, z))


static func _densify(pts: PackedVector2Array, closed: bool, step: float) -> PackedVector2Array:
	## Walk the outline putting a sample every `step` metres, so the ribbon
	## follows the hill instead of cutting through it.
	var out := PackedVector2Array()
	if pts.size() < 2:
		return pts
	var n := pts.size() if closed else pts.size() - 1
	for i in range(n):
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var d := a.distance_to(b)
		var segs := maxi(1, int(ceil(d / step)))
		for s in range(segs):
			out.append(a.lerp(b, float(s) / float(segs)))
	if not closed:
		out.append(pts[pts.size() - 1])
	return out


# ---------------------------------------------------------------- zones ---

func _draw_zone(z: Dictionary) -> void:
	var pts := WorldPlan.points_of(z)
	if pts.size() < 3:
		return
	var col := WorldPlan.kind_color(z)
	var holder := Node3D.new()
	holder.name = str(z.get("id", "zone"))
	holder.set_meta("plan_id", str(z.get("id", "")))
	_root.add_child(holder)

	if show_walls:
		var wall := _wall_mesh(_densify(pts, true, STEP), WALL_H, col)
		if wall != null:
			holder.add_child(wall)
	if show_fill:
		var fill := _fill_mesh(pts, col)
		if fill != null:
			holder.add_child(fill)
	if show_labels:
		var c := WorldPlan.center_of(z)
		var status := str(z.get("status", "planned"))
		var txt := "%s\n%s · %s" % [str(z.get("name", "")), WorldPlan.kind_label(z), status]
		var nn := WorldPlan.notes_for(str(z.get("id", ""))).size()
		if nn > 0:
			txt += "  ✎%d" % nn
		holder.add_child(_label(txt, Vector3(c.x, _g(c.x, c.y) + LABEL_LIFT, c.y), col, 0.9))


func _wall_mesh(ring: PackedVector2Array, h: float, col: Color) -> MeshInstance3D:
	## A vertical curtain around the outline: bright at the ground, fading out
	## at the top, so it never becomes a wall you cannot see the world through.
	if ring.size() < 3:
		return null
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var lo := Color(col.r, col.g, col.b, 0.55)
	var hi := Color(col.r, col.g, col.b, 0.0)
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var ay := _g(a.x, a.y)
		var by := _g(b.x, b.y)
		var a0 := Vector3(a.x, ay + 0.05, a.y)
		var b0 := Vector3(b.x, by + 0.05, b.y)
		var a1 := Vector3(a.x, ay + h, a.y)
		var b1 := Vector3(b.x, by + h, b.y)
		verts.append_array([a0, b0, b1, a0, b1, a1])
		cols.append_array([lo, lo, hi, lo, hi, hi])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	var m := _mat(Color.WHITE, 1.0)
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _fill_mesh(pts: PackedVector2Array, col: Color) -> MeshInstance3D:
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return null
	var verts := PackedVector3Array()
	for i in idx:
		var v := pts[i]
		verts.append(Vector3(v.x, _g(v.x, v.y) + FILL_LIFT, v.y))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = _mat(col, 0.14)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---------------------------------------------------------------- paths ---

func _draw_path(p: Dictionary) -> void:
	var pts := WorldPlan.points_of(p)
	if pts.size() < 2:
		return
	var col := WorldPlan.kind_color(p)
	var w := float(p.get("width", 4.0))
	var holder := Node3D.new()
	holder.name = str(p.get("id", "path"))
	holder.set_meta("plan_id", str(p.get("id", "")))
	_root.add_child(holder)

	var line := _densify(pts, false, minf(STEP, maxf(1.5, w * 0.6)))
	var ribbon := _ribbon_mesh(line, w, col, 0.45)
	if ribbon != null:
		holder.add_child(ribbon)
	## a low fence of light down the middle, so a trail reads from a distance
	if show_walls:
		var crest := _wall_strip(line, 1.4, col)
		if crest != null:
			holder.add_child(crest)
	if show_labels:
		@warning_ignore("integer_division")
		var mid := line[line.size() / 2]
		holder.add_child(_label("%s\n%s" % [str(p.get("name", "")), WorldPlan.kind_label(p)],
			Vector3(mid.x, _g(mid.x, mid.y) + 5.0, mid.y), col, 0.7))


func _ribbon_mesh(line: PackedVector2Array, w: float, col: Color, alpha: float) -> MeshInstance3D:
	if line.size() < 2:
		return null
	var half := w * 0.5
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in range(line.size()):
		var prev := line[maxi(0, i - 1)]
		var next := line[mini(line.size() - 1, i + 1)]
		var t := (next - prev)
		if t.length() < 0.001:
			t = Vector2(1, 0)
		t = t.normalized()
		var n := Vector2(-t.y, t.x) * half
		var a := line[i] + n
		var b := line[i] - n
		left.append(Vector3(a.x, _g(a.x, a.y) + FILL_LIFT, a.y))
		right.append(Vector3(b.x, _g(b.x, b.y) + FILL_LIFT, b.y))
	var verts := PackedVector3Array()
	for i in range(line.size() - 1):
		verts.append_array([left[i], right[i], right[i + 1],
							left[i], right[i + 1], left[i + 1]])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = _mat(col, alpha)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _wall_strip(line: PackedVector2Array, h: float, col: Color) -> MeshInstance3D:
	if line.size() < 2:
		return null
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var lo := Color(col.r, col.g, col.b, 0.50)
	var hi := Color(col.r, col.g, col.b, 0.0)
	for i in range(line.size() - 1):
		var a := line[i]
		var b := line[i + 1]
		var ay := _g(a.x, a.y)
		var by := _g(b.x, b.y)
		verts.append_array([
			Vector3(a.x, ay + 0.05, a.y), Vector3(b.x, by + 0.05, b.y), Vector3(b.x, by + h, b.y),
			Vector3(a.x, ay + 0.05, a.y), Vector3(b.x, by + h, b.y), Vector3(a.x, ay + h, a.y)])
		cols.append_array([lo, lo, hi, lo, hi, hi])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	var m := _mat(Color.WHITE, 1.0)
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---------------------------------------------------------------- notes ---

func _draw_note(n: Dictionary) -> void:
	var pa: Array = n.get("pos", [0, 0, 0])
	var pos := Vector3(float(pa[0]), float(pa[1]), float(pa[2]))
	var tag := str(n.get("tag", "todo"))
	var col: Color = WorldPlan.NOTE_TAG_COLOR.get(tag, Color.WHITE)
	var holder := Node3D.new()
	holder.name = str(n.get("id", "note"))
	holder.set_meta("plan_id", str(n.get("id", "")))
	holder.position = pos
	_root.add_child(holder)

	## the post
	var post := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, PIN_H, 0.09)
	post.mesh = bm
	post.position.y = PIN_H * 0.5
	post.material_override = _mat(col, 0.85)
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(post)
	## the bead on top
	var bead := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	sm.radial_segments = 8
	sm.rings = 4
	bead.mesh = sm
	bead.position.y = PIN_H
	bead.material_override = _mat(col, 0.95)
	bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(bead)

	if show_labels:
		var title := str(n.get("title", "")).strip_edges()
		if title == "":
			title = "(untitled)"
		var body := str(n.get("body", "")).strip_edges()
		var txt := "[%s] %s" % [tag, title]
		if body != "":
			var first := body.split("\n")[0]
			if first.length() > 46:
				first = first.substr(0, 44) + "…"
			txt += "\n" + first
		var lb := _label(txt, Vector3(0, PIN_H + 0.9, 0), col, 0.55)
		holder.add_child(lb)


# ---------------------------------------------------------------- label ---

func _label(text: String, pos: Vector3, col: Color, size := 0.8) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.012 * size
	l.font_size = 96
	l.outline_size = 26
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.modulate = col.lightened(0.35)
	l.render_priority = 4
	l.outline_render_priority = 3
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = true
	return l


# ---------------------------------------------------------- draft preview --

## The in-progress polygon/polyline the editor is drawing right now. Kept as a
## separate node so a redraw every click is cheap.
var _draft: Node3D = null


func set_draft(pts: PackedVector2Array, closed: bool, col: Color, width := 0.0) -> void:
	if _draft != null:
		_draft.queue_free()
		_draft = null
	if pts.is_empty():
		return
	_draft = Node3D.new()
	add_child(_draft)
	for v in pts:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.45, 2.2, 0.45)
		m.mesh = bm
		m.position = Vector3(v.x, _g(v.x, v.y) + 1.1, v.y)
		m.material_override = _mat(col, 0.9)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_draft.add_child(m)
	if pts.size() >= 2:
		var line := _densify(pts, closed, STEP)
		if width > 0.0:
			var r := _ribbon_mesh(line, width, col, 0.4)
			if r != null:
				_draft.add_child(r)
		var w := _wall_strip(line, 2.2, col) if not closed else _wall_mesh(line, 2.2, col)
		if w != null:
			_draft.add_child(w)


func clear_draft() -> void:
	if _draft != null:
		_draft.queue_free()
		_draft = null
