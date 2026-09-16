extends SceneTree
## CityGroundLook — the six on the REAL bake, photographed.
##
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . \
##       --rendering-driver opengl3 --script res://tests/CityGroundLook.gd
##
## The green suite says the layout follows the ground. This says whether a
## human would believe it. Stands each city on a mesh built from the bake's
## own heightfield — the same numbers `Cities` samples — and shoots it from
## the road, from the wall and from above.

const OUT := "user://cityshots/"
const PATCH := 560.0     ## metres of ground around the centre
const PATCH_STEP := 4.0  ## the bake's own spacing

const SHOTS := {
	"Portland": [
		["portland_1_from_the_harbour", Vector3(-30, 26, 300), Vector3(0, 6, 0), 60.0],
		["portland_2_the_south_wall", Vector3(20, 4, 250), Vector3(0, 10, 60), 70.0],
		["portland_3_aerial", Vector3(0, 300, 300), Vector3(0, 0, 0), 55.0],
	],
	"Presque Isle": [
		["presqueisle_1_from_the_road", Vector3(150, 6, 130), Vector3(0, 5, 0), 62.0],
		["presqueisle_2_aerial", Vector3(0, 190, 190), Vector3(0, 0, 0), 55.0],
	],
}


class TerrainHost extends Node3D:
	## the shape the real World has: a private terrain node, no (x, z) probe
	var _terrain: Node3D = null


func _init() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(OUT)

	var terr: Node3D = Overworld.new()
	terr.name = "Terrain"
	root.add_child(terr)
	if not terr.get("_loaded"):
		print("NO BAKE — nothing to photograph")
		quit(1)
		return
	## nothing here wants the streamer; the picture is built from the samples
	terr.set_process(false)

	var host := TerrainHost.new()
	host._terrain = terr
	root.add_child(host)
	var cities: Node = Cities.boot(host)
	print(cities.call("report"))

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.58, 0.68, 0.80)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.64, 0.68, 0.74)
	e.ambient_light_energy = 0.9
	e.fog_enabled = true
	e.fog_density = 0.0012
	e.fog_light_color = Color(0.66, 0.74, 0.84)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.rotation_degrees = Vector3(-38, 34, 0)
	sun.light_energy = 1.4

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.far = 6000.0

	for nm in SHOTS.keys():
		var lay: Dictionary = (cities.get("cities") as Dictionary)[nm]
		var cen: Vector3 = lay["centre"]
		var node: Node3D = cities.call("stage", nm)
		print("%s staged at %s (%d nodes)" % [nm, str(cen), _count(node)])
		var ground := _patch(terr, cen)
		root.add_child(ground)
		for s in SHOTS[nm]:
			cam.fov = float(s[3])
			cam.global_position = cen + (s[1] as Vector3)
			cam.look_at(cen + (s[2] as Vector3), Vector3.UP)
			await process_frame
			await process_frame
			await process_frame
			var img := root.get_viewport().get_texture().get_image()
			img.save_png(OUT + str(s[0]) + ".png")
			print("  shot ", s[0])
		cities.call("strike", nm)
		ground.queue_free()
	print("done")
	quit(0)


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


## A mesh of the bake's own surface around a city — vertex-shaded by height so
## the slope reads, and NOT built by anything the city uses, so a city that
## agrees with it agrees with the heightfield.
func _patch(terr: Node3D, centre: Vector3) -> MeshInstance3D:
	var n := int(PATCH / PATCH_STEP)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := PATCH * 0.5
	for iz in range(n):
		for ix in range(n):
			var x0 := centre.x - half + float(ix) * PATCH_STEP
			var z0 := centre.z - half + float(iz) * PATCH_STEP
			var x1 := x0 + PATCH_STEP
			var z1 := z0 + PATCH_STEP
			var p00 := Vector3(x0, terr.call("sample_height", x0, z0), z0)
			var p10 := Vector3(x1, terr.call("sample_height", x1, z0), z0)
			var p01 := Vector3(x0, terr.call("sample_height", x0, z1), z1)
			var p11 := Vector3(x1, terr.call("sample_height", x1, z1), z1)
			for tri in [[p00, p01, p11], [p00, p11, p10]]:
				for p: Vector3 in tri:
					st.set_color(_tint(terr, p))
					st.add_vertex(p)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	mi.material_override = m
	mi.name = "GroundPatch"
	return mi


func _tint(terr: Node3D, p: Vector3) -> Color:
	if bool(terr.call("is_water_at", p)):
		return Color(0.16, 0.26, 0.34)
	var t: float = clampf((p.y - 0.0) / 140.0, 0.0, 1.0)
	return Color(0.26, 0.36, 0.20).lerp(Color(0.48, 0.44, 0.33), t)
