class_name TreeImpostor
extends Node

## ===========================================================================
## The distant forest is a PHOTOGRAPH of the real tree.
##
## Lemon 2026-09-01: "completely remove the blob trees ... let's do lod
## textures, make tree blobs (like pictures of the real trees and leaves) that
## can wave around in the distance, and whatever's not being rendered isn't
## being rendered."
##
## WHAT THIS REPLACES. Overworld's `far` and `tiny` bakes built a crown out of
## three faceted bipyramids with every vertex pinned to ONE opaque texel of the
## species' leaf atlas (CROWN_LOBES / BLOB_UV). Cheap, and it read as a green
## gem on a stick from anywhere you could see it.
##
## WHAT IT DOES INSTEAD. Builds one real TreeV2 per species -- the kit model,
## the densified canopy, the real bark, the real leaf atlas, the live season --
## inside a SubViewport, renders it once against a transparent background, and
## hands Overworld a quad wearing that image. Two triangles per distant tree,
## and the far woods are literally a picture of the near woods.
##
## THE OLD FAILURE THIS DOES NOT REPEAT (Overworld, "THE CROWN IS A BLOB"):
## crossed cards UV'd across the whole leaf atlas dissolved with distance,
## because the atlas is ~66% clear texels and the mips averaged alpha under the
## cut until the woods were bare white sticks. An impostor's alpha is one
## tree-shaped silhouette hundreds of texels across. It survives every mip, and
## _dilate() below bleeds colour into the clear border so the mips have no
## black to average in either.
##
## SEASONS. A photo freezes the season it was taken in, so the season index is
## polled and the textures are re-shot when it turns -- four times a game year,
## a handful of frames each. The MESH and the MATERIAL are made once and reused,
## so a re-bake swaps a texture and nothing downstream rebuilds.
## ===========================================================================

const SHADER_PATH := "res://shaders/impostor.gdshader"
const TEX_SIZE := 320             ## render square, px. Cropped to the tree after.
const STAGE := 2                  ## mature -- the tree a wood is actually made of
const SPECIES: Array[String] = ["maple", "birch", "oak", "pine", "fir"]
const DILATE_PASSES := 3          ## push colour into the clear border before mips
const BAKE_SEED := 0x5EED         ## one fixed tree per species, every launch
const SEASON_POLL := 4.0          ## seconds between "has the year turned?" checks

## Fires once, when the first full set is baked and the meshes are valid.
## Overworld listens and rebuilds; before it there is simply no far tier.
signal impostors_ready

static var inst: TreeImpostor = null

static var _mats: Dictionary = {}     ## species -> ShaderMaterial (stable)
static var _meshes: Dictionary = {}   ## species -> ArrayMesh (stable)
static var _ready_once := false

var _season_baked := -99
var _busy := false
var _poll := 0.0


static func is_ready() -> bool:
	return _ready_once


## The quad for one species, or null before the first bake lands.
static func mesh_for(species: String) -> ArrayMesh:
	return _meshes.get(species, null)


func _ready() -> void:
	inst = self
	## NOT kicked here, on purpose. The photograph is taken at the LIVE season,
	## and the season is published by World._ready() through Wind -- which has
	## not necessarily happened when the terrain builds. Baking early gives
	## phase 0.0, the first day of spring, where foliage.gdshader holds every
	## deciduous tree BARE: the whole distant forest would be leafless maples
	## for the rest of the session. _process waits for a real value.
	_poll = 0.0


func _process(delta: float) -> void:
	if _busy:
		return
	_poll -= delta
	if _poll > 0.0:
		return
	if Wind.phase < 0.0:
		_poll = 0.25          ## nothing has published a season yet; check back
		return
	_poll = SEASON_POLL
	if _season_index() != _season_baked:
		_kick()


## Wind.phase, NOT the global shader parameter. global_shader_parameter_get()
## is editor-only -- in a running game it returns null and logs a performance
## error every call, which is exactly how the first version of this baked the
## entire far forest in a bare spring.
static func _season_index() -> int:
	return int(fposmod(maxf(Wind.phase, 0.0), 1.0) * 4.0)


func _kick() -> void:
	if _busy:
		return
	_busy = true
	_bake_all.call_deferred()


func _bake_all() -> void:
	_season_baked = _season_index()
	for sp in SPECIES:
		await _bake_one(sp)
	_busy = false
	if not _ready_once:
		_ready_once = true
		impostors_ready.emit()


## Render one species. First call also builds its quad and material; later
## calls (a season turned) only swap the texture in.
func _bake_one(species: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(TEX_SIZE, TEX_SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.world_3d = World3D.new()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)

	## Flat, generous light. The impostor shader applies the LIVE sun on top of
	## this, so what belongs in the texture is the tree at full daylight and
	## nothing else -- but it cannot be NO light, because bark.gdshader and
	## foliage.gdshader both write DIFFUSE_LIGHT from a custom light() and would
	## bake out solid black.
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.15
	key.shadow_enabled = false
	key.rotation_degrees = Vector3(-34.0, 28.0, 0.0)
	vp.add_child(key)

	## The REAL tree -- TreeV2, not TreeKit directly. TreeV2 is what densifies
	## the canopy and seeds the bark, and an impostor that skips either pops
	## visibly at the handoff.
	var rng := RandomNumberGenerator.new()
	rng.seed = BAKE_SEED + hash(species)
	var tree: TreeV2 = TreeV2.make(rng, species, STAGE, "temperate")
	## _ready() fires the moment this is parented, so both of these have to be
	## set BEFORE the add_child, not after.
	tree.scale_class = 1.0
	tree.dead = false
	vp.add_child(tree)
	## TreeV2._ready() enlists in "trees" and "choppable". This one is a prop
	## for a camera and must never answer a gameplay query -- the wildlife
	## director and the axe both walk those groups.
	tree.remove_from_group("trees")
	tree.remove_from_group("choppable")

	await get_tree().process_frame

	var box := _model_aabb(tree)
	if box.size.y <= 0.01:
		push_warning("TreeImpostor: %s built an empty AABB -- no far tier for it." % species)
		vp.queue_free()
		return

	## A SQUARE ortho frame around the whole tree: square keeps the pixels
	## isotropic, so the crop maps back to metres with one number.
	var cx := box.position.x + box.size.x * 0.5
	var cy := box.position.y + box.size.y * 0.5
	var cz := box.position.z + box.size.z * 0.5
	var span: float = maxf(maxf(box.size.x, box.size.z), box.size.y) * 1.04

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = span
	cam.near = 0.05
	cam.far = span * 6.0
	cam.position = Vector3(cx, cy, cz + span * 2.0)
	cam.current = true
	vp.add_child(cam)

	## One frame for the camera to take it, one for the frame to land.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	if img == null:
		push_warning("TreeImpostor: %s rendered nothing." % species)
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	var crop := _alpha_bounds(img)
	if crop.size.x < 2 or crop.size.y < 2:
		push_warning("TreeImpostor: %s rendered blank." % species)
		return
	img = img.get_region(crop)
	_dilate(img)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)

	var mat: ShaderMaterial = _mats.get(species, null)
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = load(SHADER_PATH)
		_mats[species] = mat
	mat.set_shader_parameter("albedo", tex)

	if not _meshes.has(species):
		## Map the crop back into model metres. The ortho frame covers `span`
		## metres over TEX_SIZE pixels, and the image's +Y runs DOWN.
		var mpp := span / float(TEX_SIZE)
		var x0 := cx - span * 0.5 + float(crop.position.x) * mpp
		var y1 := cy + span * 0.5 - float(crop.position.y) * mpp
		var rect := Rect2(x0, y1 - float(crop.size.y) * mpp,
			float(crop.size.x) * mpp, float(crop.size.y) * mpp)
		mat.set_shader_parameter("quad_h", maxf(rect.position.y + rect.size.y, 0.5))
		var m := _quad(rect)
		m.surface_set_material(0, mat)
		_meshes[species] = m


## One upright quad, pivot on the ground at x = 0 so it plants where the
## scatter put it. UV origin top-left, matching the rendered image.
static func _quad(rect: Rect2) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(rect.position.x, rect.position.y, 0.0),
		Vector3(rect.position.x + rect.size.x, rect.position.y, 0.0),
		Vector3(rect.position.x + rect.size.x, rect.position.y + rect.size.y, 0.0),
		Vector3(rect.position.x, rect.position.y + rect.size.y, 0.0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	## The billboard spins this quad in the vertex shader, so its real bounds
	## are a cylinder, not the flat rect the vertices describe. Without a custom
	## AABB Godot culls a tree the moment its flat rect turns edge-on.
	var r: float = maxf(rect.size.x, rect.size.y) * 0.5
	am.custom_aabb = AABB(Vector3(-r, rect.position.y, -r),
		Vector3(r * 2.0, rect.size.y, r * 2.0))
	return am


## Every mesh under the tree, in the TREE's own space.
static func _model_aabb(tree: Node3D) -> AABB:
	var inv := tree.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for n in _walk(tree):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var b: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


## The tight box of everything the render actually drew. Byte access, not
## get_pixel: this is 100k texels a species and GDScript per-pixel calls turn
## a bake into a visible hitch.
static func _alpha_bounds(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in range(h):
		var row := y * w * 4
		for x in range(w):
			if d[row + x * 4 + 3] < 6:
				continue
			if x < x0: x0 = x
			if x > x1: x1 = x
			if y < y0: y0 = y
			if y > y1: y1 = y
	if x1 < 0:
		return Rect2i(0, 0, 0, 0)
	## one texel of clear margin, so _dilate has somewhere to bleed into
	x0 = maxi(x0 - 1, 0)
	y0 = maxi(y0 - 1, 0)
	x1 = mini(x1 + 1, w - 1)
	y1 = mini(y1 + 1, h - 1)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


## Bleed colour outward into the clear texels, alpha untouched. Without this
## the mip chain averages the transparent BLACK background into the crown edge
## and the forest wears a halo that gets darker the further away it is.
static func _dilate(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for _p in range(DILATE_PASSES):
		var src := img.get_data()
		var dst := src.duplicate()
		for y in range(h):
			for x in range(w):
				var o := (y * w + x) * 4
				if src[o + 3] >= 6:
					continue
				var r := 0
				var g := 0
				var b := 0
				var n := 0
				## range(), not [-1, 0, 1]: an untyped array literal makes the
				## loop variable a Variant and `var sy := y + dy` then has no
				## inferable type, which is a PARSE error, not a warning.
				for dy in range(-1, 2):
					var sy: int = y + dy
					if sy < 0 or sy >= h:
						continue
					for dx in range(-1, 2):
						var sx: int = x + dx
						if sx < 0 or sx >= w:
							continue
						var so := (sy * w + sx) * 4
						if src[so + 3] < 6:
							continue
						r += src[so]
						g += src[so + 1]
						b += src[so + 2]
						n += 1
				if n == 0:
					continue
				dst[o] = r / n
				dst[o + 1] = g / n
				dst[o + 2] = b / n
		var mips := img.has_mipmaps()
		img.set_data(w, h, mips, Image.FORMAT_RGBA8, dst)
