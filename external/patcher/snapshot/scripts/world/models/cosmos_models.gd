class_name CosmosModels
extends RefCounted
## The characters' models for the 3D game, made cheap to draw: Stage3D's
## model (art/<id>_3d/<id>.glb - one surface a material: the pirate has 18)
## merged, once a run, into one physically based surface - each part's
## albedo in its vertices (COLOR), its metallic, roughness and glow in CUSTOM0
## (Stage3D.surface_look), the old ink outline left out - drawn by pbr_vc.
## Skinning kept (bones, weights, the same skin). A crowd of characters is
## one draw each instead of a dozen and more.
## Worn: each vertex at rest (and its normal's up) in CUSTOM1 - pbr_vc's grime,
## dust, chipped paint and scratches stay put on the parts as they move; the
## shared noise (Cosmos.noise_ready) given to the materials once it's made.
## Recolourable: each vertex's slot in CUSTOM0.w (1 armour, 2 accent, 3 glow)
## - apply(root, id, colours) gives the model a material that sets them
## (pbr_vc's recolor_* parameters): the towns' people in their empire's colours.
##   CosmosModels.apply(model_root, "pirate")
##   CosmosModels.apply(model_root, "player", [main, accent, glow])
## Modular: `hide` leaves out the parts whose material starts with one of
## its prefixes - the Minoan android carries its rifle, bow or labrys
##   CosmosModels.apply(root, "minoan", [], ["MIN_Bow", "MIN_Axe"])

const PBR := preload("res://shaders/pbr_vc.gdshader")

static var _meshes := {}         # id -> ArrayMesh


## A character's merged meshes and its table forgotten (its model.json changed: the mesh editor
## saved its materials) - made again the next time one is dressed.
static func forget(id: String) -> void:
	for k in _meshes.keys():
		if str(k) == id or str(k).begins_with(id + "|"):
			_meshes.erase(k)
	Stage3D._infos.erase(id)
static var _mats: Array = []
static var _tinted := {}         # str(colours) -> ShaderMaterial
static var _noise: Texture3D = null


## Gives the model under `root` (its "Body" mesh) the merged mesh.
static func apply(root: Node, id: String, recolor: Array = [], hide: Array = []) -> void:
	var mi: MeshInstance3D = root.find_child("Body", true, false)
	if mi == null:
		return
	root.set_meta("model_id", id)   # (which character it is: the Live Editor's Animation tab)
	var src: Mesh = mi.mesh
	var extra := _bound_parts(root, mi)
	if not extra.is_empty():
		# (parts added in the mesh editor and skinned to its skeleton: drawn as the Body, merged into it)
		if not _meshes.has(id + ("|" + ",".join(hide) if not hide.is_empty() else "")):
			src = _with_parts(mi, extra)
		for e: MeshInstance3D in extra:
			e.visible = false
	var m := merged(id, src, hide)
	mi.mesh = m
	if _mats.is_empty():
		var m0 := ShaderMaterial.new()
		m0.shader = PBR
		_mats = [m0]
	var mat: ShaderMaterial = _mats[0]
	if not recolor.is_empty():
		var key := str(recolor)
		if not _tinted.has(key):
			var mt := ShaderMaterial.new()
			mt.shader = PBR
			for k in 3:
				var c: Color = recolor[k]
				var l := c.srgb_to_linear()
				mt.set_shader_parameter(["recolor_main", "recolor_accent", "recolor_glow"][k], Color(l.r, l.g, l.b, c.a))
			if _noise != null:
				_wear(mt)
			_tinted[key] = mt
		mat = _tinted[key]
	_give_noise()
	for i in m.get_surface_count():
		mi.set_surface_override_material(i, mat)


## The other meshes under `root` skinned to the Body's skeleton (parts saved with weights).
static func _bound_parts(root: Node, body: MeshInstance3D) -> Array:
	var out := []
	var sk := body.get_node_or_null(body.skeleton)
	if sk == null or body.skin == null:
		return out
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var p := n as MeshInstance3D
		if p == body or p.mesh == null or p.skin == null or p.get_node_or_null(p.skeleton) != sk:
			continue
		out.append(p)
	return out


## The Body's mesh with parts `extra`'s surfaces added - their bones named as the Body's skin
## names them, as many a vertex as the Body's.
static func _with_parts(body: MeshInstance3D, extra: Array) -> ArrayMesh:
	var out := ArrayMesh.new()
	var src: Mesh = body.mesh
	var per := 4
	for i in src.get_surface_count():
		var a := src.surface_get_arrays(i)
		var nv: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if a[Mesh.ARRAY_BONES] != null and nv > 0:
			per = (a[Mesh.ARRAY_BONES] as PackedInt32Array).size() / nv
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(i))
	var skin: Skin = body.skin
	var sk := body.get_node(body.skeleton) as Skeleton3D
	var bind_of := {}   # bone -> the Body's bind
	for k in skin.get_bind_count():
		var b := skin.get_bind_bone(k)
		bind_of[b if b >= 0 else sk.find_bone(skin.get_bind_name(k))] = k
	for p: MeshInstance3D in extra:
		var map := PackedInt32Array()   # its bind -> the Body's
		for k in p.skin.get_bind_count():
			var b := p.skin.get_bind_bone(k)
			if b < 0:
				b = sk.find_bone(p.skin.get_bind_name(k))
			map.append(bind_of.get(b, 0))
		for i in p.mesh.get_surface_count():
			var a := p.mesh.surface_get_arrays(i)
			var nv: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if a[Mesh.ARRAY_BONES] == null or nv == 0:
				continue
			var bs: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var pp := bs.size() / nv
			var same := pp == per
			for k in map.size():
				if map[k] != k:
					same = false
					break
			if same:
				# (skinned with the Body's own skin - an ECurve object's solids: its bones as they are, no
				# vertex by vertex renumbering - 90 ms saved on a character of ninety solids)
				a[Mesh.ARRAY_TANGENT] = null
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
				out.surface_set_material(out.get_surface_count() - 1, p.mesh.surface_get_material(i))
				continue
			var nb := PackedInt32Array()
			var nw := PackedFloat32Array()
			for v in nv:
				for k in per:
					nb.append(map[bs[v * pp + k]] if k < pp and bs[v * pp + k] < map.size() else 0)
					nw.append(ws[v * pp + k] if k < pp else 0.0)
			a[Mesh.ARRAY_BONES] = nb
			a[Mesh.ARRAY_WEIGHTS] = nw
			a[Mesh.ARRAY_TANGENT] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
			out.surface_set_material(out.get_surface_count() - 1, p.mesh.surface_get_material(i))
	return out


## The noise for the wear, once Cosmos has made it (till then pbr_vc's own).
static func _give_noise() -> void:
	if _noise != null:
		return
	_noise = Cosmos.noise_ready()
	if _noise == null:
		return
	for m in _mats + _tinted.values():
		_wear(m)


static func _wear(m: ShaderMaterial) -> void:
	m.set_shader_parameter("noise_tex", _noise)
	m.set_shader_parameter("has_noise", 1.0)


static func merged(id: String, src: Mesh, hide: Array = []) -> ArrayMesh:
	var key := id + ("|" + ",".join(hide) if not hide.is_empty() else "")
	if _meshes.has(key):
		return _meshes[key]
	var out := _merge(id, src, hide)
	_meshes[key] = out
	return out


## (worker) A character's merged mesh made from its scene `ps` - its Body and the parts skinned with it
## (an ECurve object's solids) - nothing remembered: Stage3D.warm makes it there, keep() keeps it.
## Stage3D.info(id) read before (on the main thread).
static func premerge(ps: PackedScene, id: String) -> ArrayMesh:
	if ps == null:
		return null
	var root := ps.instantiate()
	var body: MeshInstance3D = root.find_child("Body", true, false)
	var out: ArrayMesh = null
	if body and body.mesh:
		var extra := _bound_parts(root, body)
		out = _merge(id, _with_parts(body, extra) if not extra.is_empty() else body.mesh, [])
	root.free()
	return out


## A merged mesh premerge() made kept as `id`'s (unless one's been made meanwhile).
static func keep(id: String, m: ArrayMesh) -> void:
	if m != null and not _meshes.has(id):
		_meshes[id] = m


static func _merge(id: String, src: Mesh, hide: Array) -> ArrayMesh:
	var table: Dictionary = Stage3D.info(id).get("materials", {})
	var parts: Array = []
	for i in src.get_surface_count():
		var nm := src.surface_get_material(i).resource_name if src.surface_get_material(i) else ""
		var look := Stage3D.surface_look(nm, str(table.get(nm, {}).get("kind", "toon")))
		# (a material edited in the mesh editor: its own metal, roughness and glow - model.json's
		# table has them - over the look its name gives)
		var row: Dictionary = table.get(nm, {})
		for k in [["metal", "metal"], ["rough", "rough"], ["emit", "emit"]]:
			if row.has(k[0]):
				look = look.duplicate()
				look[k[1]] = float(row[k[0]])
		if not look["hidden"] and not hide.any(func(h): return nm.begins_with(h)):
			parts.append([i, look, table.get(nm, {})])
	var out := ArrayMesh.new()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var custom := PackedFloat32Array()
	var rest := PackedFloat32Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	for part in parts:
		var a := src.surface_get_arrays(part[0])
		var nm: String = src.surface_get_material(part[0]).resource_name if src.surface_get_material(part[0]) else ""
		var look: Dictionary = part[1]
		var c: Array = part[2].get("color", [0.8, 0.8, 0.8])
		var col := Color(c[0], c[1], c[2]).srgb_to_linear()   # (vertex colours are linear)
		var emit := float(look["emit"]) * float(part[2].get("strength", 1.0))
		var base := verts.size()
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		verts.append_array(vs)
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		norms.append_array(ns)
		bones.append_array(a[Mesh.ARRAY_BONES])
		weights.append_array(a[Mesh.ARRAY_WEIGHTS])
		var slot := 1.0 if nm.begins_with("AUT_Armor") else (2.0 if nm.begins_with("AUT_Red") else (3.0 if nm.begins_with("AUT_Glow") else 0.0))
		for k in vs.size():
			cols.append(col)
			custom.append_array([look["metal"], look["rough"], emit, slot])
			rest.append_array([vs[k].x, vs[k].y, vs[k].z, ns[k].y])
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for k in ix:
			idx.append(k + base)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_CUSTOM0] = custom
	arr[Mesh.ARRAY_CUSTOM1] = rest
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	arr[Mesh.ARRAY_INDEX] = idx
	var fmt := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT | Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	out.surface_set_name(0, "pbr")
	LodKit.later(out, [arr], fmt)   # (its levels of detail: made on a worker, swapped in - LodKit)
	return out
