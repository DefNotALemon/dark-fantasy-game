class_name LeafBurst
extends MeshInstance3D

## ===========================================================================
## The canopy coming off a tree on the way down.  (docs/TREES_v3_PSX.md §5)
##
## Lemon's call: leaves SHOULD shed when a tree is knocked over — just properly,
## as a burst of real leaves fluttering out of the crown, not as foliage that
## pops out of existence.
##
## Two halves work together. The tree's own canopy thins card-by-card through
## the `shed` uniform on psx_foliage (FallenTrunk ramps it during the fall), and
## this node throws the difference: leaf quads LIFTED OUT OF THAT TREE'S OWN
## CANOPY MESH, so they are the same leaves, in the same season, at the same
## size. One mesh, one draw call, all the motion in the vertex shader.
## ===========================================================================

const SHADER := "res://shaders/psx_leaffall.gdshader"
const LIFETIME := 5.2
const MAX_CARDS := 140
## A pack canopy is a dozen FAT clumps -- one clump is most of a branch's worth
## of leaves and can be a metre and a half across. Thrown at full size they
## read as bedsheets, which is the same mistake §23 caught in the old canopy.
## Each card shrinks about its own centre on the way out.
const CARD_SCALE := 0.30

var _t := 0.0
var _mat: ShaderMaterial


## Pull the canopy off a felled tree's model and throw it.
## `model` is the tree's instantiated GLB; `world` is where the burst lives on
## (never the tree — it is about to free itself).
static func spawn_from(model: Node3D, atlas: String, region: String,
		world: Node, count := 64) -> LeafBurst:
	if model == null or world == null:
		return null
	var src: MeshInstance3D = null
	for n in _all(model):
		var mi := n as MeshInstance3D
		if mi != null and mi.name.begins_with("Foliage") and mi.mesh != null:
			src = mi
			break
	if src == null:
		return null

	var burst := LeafBurst.new()
	var built := burst._build(src, mini(count, MAX_CARDS))
	if not built:
		return null
	burst._mat = PSXNature.materials(atlas, region, false)[1].duplicate() as ShaderMaterial
	## Same four atlases, different shader — copy the bindings across rather
	## than working out the region's recipe a second time.
	var names := ["atlas_spring", "atlas_summer", "atlas_autumn", "atlas_winter"]
	var fall := ShaderMaterial.new()
	fall.shader = load(SHADER)
	for n2 in names:
		fall.set_shader_parameter(n2, burst._mat.get_shader_parameter(n2))
	burst._mat = fall
	burst.material_override = fall
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(burst)
	burst.global_transform = src.global_transform
	return burst


static func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _build(src: MeshInstance3D, count: int) -> bool:
	var arrays: Array = src.mesh.surface_get_arrays(0)
	var sv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var su: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var si: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if sv.is_empty() or su.is_empty():
		return false
	if si.is_empty():
		si = PackedInt32Array(range(sv.size()))
	@warning_ignore("integer_division")
	var tri_count := si.size() / 3
	if tri_count <= 0:
		return false

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var custom := PackedFloat32Array()

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(src.get_path())
	## Throw MORE leaves than the canopy held: a pack canopy is a dozen fat
	## clumps, and a dozen clumps sinking to the floor reads as the tree losing
	## its hat. Jittered copies read as leaves.
	for i in range(count):
		var t := (rng.randi() % tri_count) * 3
		var a := sv[si[t]]
		var b := sv[si[t + 1]]
		var c := sv[si[t + 2]]
		var centre := (a + b + c) / 3.0
		var jitter := Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.5, 0.5),
			rng.randf_range(-0.9, 0.9))
		var sd := rng.randf()
		var shrink := CARD_SCALE * rng.randf_range(0.75, 1.35)
		var base := verts.size()
		for v in [a, b, c]:
			verts.append(centre + (v - centre) * shrink + jitter)
			norms.append(Vector3.UP)
			custom.append_array([centre.x + jitter.x, centre.y + jitter.y,
				centre.z + jitter.z, sd])
		uvs.append(su[si[t]])
		uvs.append(su[si[t + 1]])
		uvs.append(su[si[t + 2]])
		idx.append_array([base, base + 1, base + 2])

	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_INDEX] = idx
	out[Mesh.ARRAY_CUSTOM0] = custom

	var fmt := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, fmt)
	mesh = am
	## The AABB grows enormously once they start falling; without this the whole
	## burst gets frustum-culled the moment the crown leaves the original box.
	custom_aabb = AABB(Vector3(-14, -14, -14), Vector3(28, 28, 28))
	return true


func _ready() -> void:
	add_to_group("leaf_bursts")


func _process(delta: float) -> void:
	_t += delta
	if _mat != null:
		_mat.set_shader_parameter("fall_t", clampf(_t / LIFETIME, 0.0, 1.0))
	if _t >= LIFETIME:
		queue_free()
