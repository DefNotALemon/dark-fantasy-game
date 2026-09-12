class_name BuiltPiece
extends StaticBody3D

## ===========================================================================
## A PLACED PIECE — scripts/BuiltPiece.gd
##
## One wall, one floor, one barrel. Knows what it is (`piece`), what it is
## made of (`mat_id`), and how to write itself down. That is all.
##
## Group "built" + meta "built": World.save_state skips these, because the god
## editor owns them — they live in design/build_placements.json and come back
## at boot whether or not you loaded a save. A building you laid out should
## not vanish because you started a new run.
##
## ONE EXCEPTION, and it earns itself: a "firepit" grows a `Firepit` child,
## because a fire is the only piece in the kit with a state that changes while
## nobody is looking at it. Its fuel rides in this piece's own save dict, so a
## camp you banked before you slept is still warm when you get up.
## ===========================================================================

var piece := "wall"
var mat_id := ""

var fire: Firepit = null          ## only on "firepit"; null everywhere else
var _fire_restore: Dictionary = {}


static func make(piece_id: String, material_id := "", scale_f := 1.0) -> BuiltPiece:
	var b := BuiltPiece.new()
	b.piece = piece_id
	b.mat_id = material_id if material_id != "" else BuildKit.default_mat(piece_id)
	BuildKit.build_into(b, b.piece, b.mat_id)
	if scale_f != 1.0:
		b.scale = Vector3.ONE * scale_f
	return b


func _ready() -> void:
	add_to_group("built")
	add_to_group("editor_placed")
	set_meta("built", true)
	if get_child_count() == 0:
		## restored from disk before the mesh was made
		BuildKit.build_into(self, piece, mat_id)
	_attach_fire()


func _attach_fire() -> void:
	## Idempotent — _ready can run after a re-parent, and a piece restored from
	## disk has already been through from_dict.
	if piece != "firepit":
		return
	if fire != null and is_instance_valid(fire):
		return
	for c in get_children():
		if c is Firepit:
			fire = c as Firepit
			break
	if fire == null:
		fire = Firepit.make()
		add_child(fire)
	fire.boot()
	if not _fire_restore.is_empty():
		fire.apply_dict(_fire_restore)
		_fire_restore = {}


func save_dict() -> Dictionary:
	## global_position only exists inside the tree; a piece being written out
	## while detached (a test, a queued free) still has its local one, and for
	## a direct child of World the two are the same number anyway.
	var p := global_position if is_inside_tree() else position
	var d := {
		"kind": "piece",
		"piece": piece,
		"mat": mat_id,
		"pos": [p.x, p.y, p.z],
		"rot": rotation.y,
		"scale": scale.x,
	}
	if fire != null and is_instance_valid(fire):
		d["fire"] = fire.to_dict()
	elif not _fire_restore.is_empty():
		## Written out before it ever entered the tree: do not drop the state.
		d["fire"] = _fire_restore.duplicate()
	return d


static func from_dict(d: Dictionary) -> BuiltPiece:
	var b := BuiltPiece.new()
	b.piece = str(d.get("piece", "wall"))
	b.mat_id = str(d.get("mat", ""))
	if b.mat_id == "":
		b.mat_id = BuildKit.default_mat(b.piece)
	BuildKit.build_into(b, b.piece, b.mat_id)
	var p: Array = d.get("pos", [0, 0, 0])
	b.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	b.rotation.y = float(d.get("rot", 0.0))
	var s := float(d.get("scale", 1.0))
	if s != 1.0:
		b.scale = Vector3.ONE * s
	var fd: Variant = d.get("fire", null)
	if typeof(fd) == TYPE_DICTIONARY:
		b._fire_restore = (fd as Dictionary).duplicate()
	return b
