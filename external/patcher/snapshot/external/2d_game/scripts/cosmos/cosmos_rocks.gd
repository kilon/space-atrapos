class_name CosmosRocks
extends Node3D
## An asteroid field in the 3D game (Cosmos): a few hundred rocks in a loose
## flattened cloud - three lumpy rock meshes (spheres pushed about by noise),
## drawn as multimeshes (one draw each), tumbling in their shader. `rocks`
## keeps every rock's place and size (the ship bumps into them).

const COUNT := 320
const SPREAD := 2600.0
const SHADER := preload("res://shaders/cosmos/rock.gdshader")

var rocks: Array = []           # [local position, radius]


func setup(seed: int, noise: Texture3D) -> void:
	name = "Asteroids"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("noise_tex", noise)
	m.set_shader_parameter("tone", Color(0.42, 0.38, 0.34).lerp(Color(0.5, 0.42, 0.36), rng.randf()))
	var kinds := 3
	var per: Array = []
	for k in kinds:
		per.append([])
	for i in COUNT:
		var r := pow(rng.randf(), 2.2) * 70.0 + 4.0
		var p := Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 0.25), rng.randfn(0.0, 1.0)) * SPREAD * 0.5
		rocks.append([p, r])
		per[i % kinds].append([p, r, rng.randf(), Vector3(rng.randf(), rng.randf(), rng.randf())])
	for k in kinds:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _rock_mesh(rng.randi())
		mm.instance_count = per[k].size()
		for i in per[k].size():
			var e: Array = per[k][i]
			var b := Basis.from_euler(e[3] * TAU).scaled(Vector3.ONE * e[1])
			mm.set_instance_transform(i, Transform3D(b, e[0]))
			mm.set_instance_custom_data(i, Color(e[3].x, e[3].y, e[3].z, e[2]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		add_child(mmi)


## A lumpy unit rock: a sphere's vertices pushed in and out by noise.
static func _rock_mesh(seed: int) -> ArrayMesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 20
	s.rings = 10
	var arr := s.get_mesh_arrays()
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 0.9
	n.fractal_octaves = 3
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var d := verts[i].normalized()
		verts[i] = d * (1.0 + n.get_noise_3dv(d * 1.3) * 0.45) * Vector3(1.0, 0.75 + 0.2 * (seed % 3) / 2.0, 0.9)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	return st.commit()
