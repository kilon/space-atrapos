extends RefCounted
## The mesh editor's files: finding the models (the game's and the mod's),
## reading them (glTF / glb, OBJ, a mesh resource), writing glb, and the
## primitives a new part starts from. Static; reading runs on worker threads
## (nothing here touches the scene tree).

const EXTS := ["glb", "gltf", "obj", "tres", "res"]
const SKIP := ["res://.godot", "res://external", "res://addons", "res://builds", "res://export", "res://.git", "res://art/overrides"]
const PRIMITIVES := ["box", "cylinder", "cone", "sphere", "plane", "torus"]


## Every model under res:// (and the mod's own files when `mod_root` isn't ""):
## res:// paths, the game's characters (art/*_3d/) first.
static func scan(mod_root := "") -> PackedStringArray:
	var found := {}
	_walk("res://", found)
	if mod_root != "":
		var mod := {}
		_walk(mod_root, mod)
		for p in mod:
			found["res://" + str(p).trim_prefix(mod_root)] = true
	var out := PackedStringArray(found.keys())
	out.sort()
	var chars := PackedStringArray()
	var rest := PackedStringArray()
	for p in out:
		(chars if is_character(p) else rest).append(p)
	chars.append_array(rest)
	return chars


static func _walk(dir: String, out: Dictionary) -> void:
	if dir.trim_suffix("/") in SKIP:
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.include_hidden = false
	for f in d.get_files():
		var name := f.trim_suffix(".remap").trim_suffix(".import")
		if name != f and f.ends_with(".import") and FileAccess.file_exists(dir.path_join(name)):
			continue   # (the file itself is listed)
		var ext := name.get_extension().to_lower()
		if not ext in EXTS:
			continue
		var p := dir.path_join(name)
		if ext == "tres" and not _is_mesh_tres(dir.path_join(f)):
			continue
		if ext == "res" and not name.to_lower().contains("mesh"):
			continue
		out[p] = true
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_walk(dir.path_join(sub), out)


static func _is_mesh_tres(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var head := f.get_line()
	return head.contains("Mesh\"") and not head.contains("MeshLibrary")


## One of the Blender-made characters (art/<id>_3d/), rebuilt by the pipeline.
static func is_character(path: String) -> bool:
	return path.begins_with("res://art/") and path.get_base_dir().ends_with("_3d")


## Reads the model at `file` (an actual file: res:// or the mod's) - a root
## Node3D with its parts, skeleton and animations. Null if it can't.
static func read(file: String) -> Node3D:
	var ext := file.get_extension().to_lower()
	match ext:
		"glb", "gltf":
			if FileAccess.file_exists(file):
				var doc := GLTFDocument.new()
				var st := GLTFState.new()
				if doc.append_from_file(file, st) == OK:
					var n := doc.generate_scene(st)
					if n is Node3D:
						n.name = file.get_file().get_basename()
						return n
					if n:
						n.free()
			if file.begins_with("res://") and ResourceLoader.exists(file):   # (an exported game: the imported scene)
				var ps = ResourceLoader.load(file)
				if ps is PackedScene:
					var n: Node = ps.instantiate()
					if n is Node3D:
						return n
					n.free()
		"obj":
			var m: Mesh = obj_mesh(file) if FileAccess.file_exists(file) else null
			if m == null and file.begins_with("res://") and ResourceLoader.exists(file):
				m = ResourceLoader.load(file) as Mesh
			if m:
				return _wrap(m, file)
		"tres", "res":
			var r = ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE)
			if r is Mesh:
				return _wrap(r.duplicate(true), file)
	return null


static func _wrap(m: Mesh, file: String) -> Node3D:
	var root := Node3D.new()
	root.name = file.get_file().get_basename()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = m
	root.add_child(mi)
	mi.owner = root
	return root


## A Wavefront OBJ (v / vt / vn / f, polygons as fans; materials by `usemtl`
## become surfaces).
static func obj_mesh(file: String) -> ArrayMesh:
	var text := FileAccess.get_file_as_string(file)
	if text == "":
		return null
	var v := PackedVector3Array()
	var vt := PackedVector2Array()
	var vn := PackedVector3Array()
	var groups := {}   # material name -> SurfaceTool
	var order := []
	var st: SurfaceTool = null
	var cur := ""
	for line in text.split("\n"):
		var w := line.strip_edges().split(" ", false)
		if w.is_empty():
			continue
		match w[0]:
			"v":
				if w.size() >= 4:
					v.append(Vector3(w[1].to_float(), w[2].to_float(), w[3].to_float()))
			"vt":
				if w.size() >= 3:
					vt.append(Vector2(w[1].to_float(), 1.0 - w[2].to_float()))
			"vn":
				if w.size() >= 4:
					vn.append(Vector3(w[1].to_float(), w[2].to_float(), w[3].to_float()))
			"usemtl":
				cur = w[1] if w.size() > 1 else ""
				st = null
			"f":
				if st == null:
					if not groups.has(cur):
						var s := SurfaceTool.new()
						s.begin(Mesh.PRIMITIVE_TRIANGLES)
						groups[cur] = s
						order.append(cur)
					st = groups[cur]
				var corners := []
				for k in range(1, w.size()):
					var ix := w[k].split("/")
					var c := [_obj_i(ix[0], v.size()), -1, -1]
					if ix.size() > 1 and ix[1] != "":
						c[1] = _obj_i(ix[1], vt.size())
					if ix.size() > 2 and ix[2] != "":
						c[2] = _obj_i(ix[2], vn.size())
					corners.append(c)
				for k in range(1, corners.size() - 1):
					for c in [corners[0], corners[k + 1], corners[k]]:   # (OBJ is counter-clockwise; Godot's front faces are clockwise)
						if c[2] >= 0 and c[2] < vn.size():
							st.set_normal(vn[c[2]])
						if c[1] >= 0 and c[1] < vt.size():
							st.set_uv(vt[c[1]])
						if c[0] >= 0 and c[0] < v.size():
							st.add_vertex(v[c[0]])
	var mesh := ArrayMesh.new()
	for g in order:
		var s: SurfaceTool = groups[g]
		if vn.is_empty():
			s.generate_normals()
		s.index()
		s.commit(mesh)
		mesh.surface_set_name(mesh.get_surface_count() - 1, g)
	return mesh if mesh.get_surface_count() > 0 else null


static func _obj_i(s: String, n: int) -> int:
	var i := s.to_int()
	return i - 1 if i > 0 else n + i


## Writes the scene under `root` as a glb (or .gltf) at `file`: parts,
## skeleton, skin and animations.
static func write(root: Node, file: String) -> int:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(root, st)
	if err != OK:
		return err
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	return doc.write_to_filesystem(st, file)


## A primitive as an editable mesh, about a metre across.
static func primitive(kind: String) -> ArrayMesh:
	var p: PrimitiveMesh
	match kind:
		"box":
			p = BoxMesh.new()
		"cylinder":
			var c := CylinderMesh.new()
			c.top_radius = 0.5; c.bottom_radius = 0.5; c.height = 1.0; c.radial_segments = 24; c.rings = 1
			p = c
		"cone":
			var c := CylinderMesh.new()
			c.top_radius = 0.0; c.bottom_radius = 0.5; c.height = 1.0; c.radial_segments = 24; c.rings = 1
			p = c
		"sphere":
			var s := SphereMesh.new()
			s.radius = 0.5; s.height = 1.0; s.radial_segments = 24; s.rings = 12
			p = s
		"plane":
			var pl := PlaneMesh.new()
			pl.size = Vector2(1, 1)
			p = pl
		"torus":
			var t := TorusMesh.new()
			t.inner_radius = 0.3; t.outer_radius = 0.5; t.rings = 24; t.ring_segments = 12
			p = t
		_:
			return null
	var a := p.get_mesh_arrays()
	a[Mesh.ARRAY_TANGENT] = null
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	m.resource_name = kind.capitalize()
	return m


## A physically based material for a new part (and the presets' base).
static func default_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "Default"
	m.albedo_color = Color(0.72, 0.72, 0.74)
	m.metallic = 0.6
	m.roughness = 0.4
	return m


## The materials offered besides a model's own: the game's looks
## ([name, colour, metallic, roughness, emission colour, emission energy]).
const PRESETS := [
	["Bronze", Color(0.72, 0.45, 0.2), 1.0, 0.35, Color.BLACK, 0.0],
	["Gold", Color(1.0, 0.78, 0.34), 1.0, 0.25, Color.BLACK, 0.0],
	["Steel", Color(0.62, 0.64, 0.68), 1.0, 0.3, Color.BLACK, 0.0],
	["Dark metal", Color(0.16, 0.17, 0.2), 0.9, 0.45, Color.BLACK, 0.0],
	["Painted armour", Color(0.85, 0.82, 0.75), 0.3, 0.45, Color.BLACK, 0.0],
	["Minoan red", Color(0.62, 0.12, 0.08), 0.2, 0.5, Color.BLACK, 0.0],
	["Navy", Color(0.08, 0.12, 0.3), 0.3, 0.5, Color.BLACK, 0.0],
	["Cloth", Color(0.8, 0.74, 0.62), 0.0, 0.9, Color.BLACK, 0.0],
	["Stone", Color(0.7, 0.66, 0.6), 0.0, 0.85, Color.BLACK, 0.0],
	["Glow (cyan)", Color(0.2, 0.8, 1.0), 0.0, 0.4, Color(0.3, 0.85, 1.0), 3.0],
	["Glow (amber)", Color(1.0, 0.6, 0.2), 0.0, 0.4, Color(1.0, 0.6, 0.2), 3.0],
]


static func preset(i: int) -> StandardMaterial3D:
	var p: Array = PRESETS[i]
	var m := StandardMaterial3D.new()
	m.resource_name = p[0]
	m.albedo_color = p[1]
	m.metallic = p[2]
	m.roughness = p[3]
	if p[5] > 0.0:
		m.emission_enabled = true
		m.emission = p[4]
		m.emission_energy_multiplier = p[5]
	return m
