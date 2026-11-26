class_name CosmosModels
extends RefCounted
## The characters' models for the 3D game, made cheap to draw: Stage3D's
## model (art/<id>_3d/<id>.glb - one surface a material: the pirate has 18)
## merged, once a run, into one physically based surface - each part's
## albedo in its vertices (COLOR), its metallic, roughness and glow in CUSTOM0
## (Stage3D.surface_look), the old ink outline left out - drawn by pbr_vc.
## Skinning kept (bones, weights, the same skin). A crowd of characters is
## one draw each instead of a dozen and more.
##   CosmosModels.apply(model_root, "pirate")

const PBR := preload("res://shaders/pbr_vc.gdshader")

static var _meshes := {}         # id -> ArrayMesh
static var _mats: Array = []


## Gives the model under `root` (its "Body" mesh) the merged mesh.
static func apply(root: Node, id: String) -> void:
	var mi: MeshInstance3D = root.find_child("Body", true, false)
	if mi == null:
		return
	var m := merged(id, mi.mesh)
	mi.mesh = m
	if _mats.is_empty():
		var m0 := ShaderMaterial.new()
		m0.shader = PBR
		_mats = [m0]
	for i in m.get_surface_count():
		mi.set_surface_override_material(i, _mats[0])


static func merged(id: String, src: Mesh) -> ArrayMesh:
	if _meshes.has(id):
		return _meshes[id]
	var table: Dictionary = Stage3D.info(id).get("materials", {})
	var parts: Array = []
	for i in src.get_surface_count():
		var nm := src.surface_get_material(i).resource_name if src.surface_get_material(i) else ""
		var look := Stage3D.surface_look(nm, str(table.get(nm, {}).get("kind", "toon")))
		if not look["hidden"]:
			parts.append([i, look, table.get(nm, {})])
	var out := ArrayMesh.new()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var custom := PackedFloat32Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	for part in parts:
		var a := src.surface_get_arrays(part[0])
		var look: Dictionary = part[1]
		var c: Array = part[2].get("color", [0.8, 0.8, 0.8])
		var col := Color(c[0], c[1], c[2]).srgb_to_linear()   # (vertex colours are linear)
		var emit := float(look["emit"]) * float(part[2].get("strength", 1.0))
		var base := verts.size()
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		verts.append_array(vs)
		norms.append_array(a[Mesh.ARRAY_NORMAL])
		bones.append_array(a[Mesh.ARRAY_BONES])
		weights.append_array(a[Mesh.ARRAY_WEIGHTS])
		for k in vs.size():
			cols.append(col)
			custom.append_array([look["metal"], look["rough"], emit, 0.0])
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for k in ix:
			idx.append(k + base)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_CUSTOM0] = custom
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	arr[Mesh.ARRAY_INDEX] = idx
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	out.surface_set_name(0, "pbr")
	_meshes[id] = out
	return out
