extends RefCounted
## The mesh editor's shape library: data/shapes.json - each shape a generator and its
## parameters (shapes.gd makes it), or a mesh of its own ("gen": "mesh", its arrays in
## a .res under art/shapes/). The 120 built in are marked "builtin". Saved where
## EditTarget says: the game's data/shapes.json, or - in a mod - the mod's
## data/shapes.json.merge (only the shapes the mod adds, changes or removes; Mods
## merges it over the game's list as the game starts).
##   {"version": 1, "categories": [...], "shapes": {id: {name, cat, gen, params, builtin}}}

const Shapes := preload("res://scripts/editor/mesh/shapes.gd")
const FILE := "res://data/shapes.json"
const MERGE := "res://data/shapes.json.merge"
const MESH_DIR := "res://art/shapes/"
const USER_CAT := "Mine"

var categories: Array = []
## id -> entry (in the order they're listed)
var shapes := {}
## The ids a mod adds, changes or removes (id -> entry, or {"deleted": true}).
var _mod := {}


## Reads the library (the game's list, the mod's changes over it).
func load_all() -> void:
	shapes.clear()
	_mod.clear()
	var d = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if not d is Dictionary:
		d = {}
	categories = (d.get("categories", []) as Array).duplicate()
	var all: Dictionary = d.get("shapes", {})
	for id in all:
		shapes[id] = (all[id] as Dictionary).duplicate(true)
	if EditTarget.is_mod():
		var mf := EditTarget.root() + MERGE.trim_prefix("res://")
		var m = JSON.parse_string(FileAccess.get_file_as_string(mf)) if FileAccess.file_exists(mf) else null
		if m is Dictionary:
			var add: Dictionary = m.get("shapes", {})
			for id in add:
				_mod[id] = (add[id] as Dictionary).duplicate(true)
				if add[id].get("deleted", false):
					shapes.erase(id)
				else:
					shapes[id] = Mods.merge(shapes.get(id, {}), add[id])
	for id in shapes.keys():
		if shapes[id].get("deleted", false):
			shapes.erase(id)
	for id in shapes:
		var c := str(shapes[id].get("cat", USER_CAT))
		if not c in categories:
			categories.append(c)


## The ids in `cat` ("": all) whose name or category has every word of `words`.
func ids(cat := "", words := "") -> Array:
	var ws := words.to_lower().split(" ", false)
	var out := []
	for id in shapes:
		var e: Dictionary = shapes[id]
		if cat != "" and str(e.get("cat", "")) != cat:
			continue
		var hay := (str(e.get("name", id)) + " " + str(e.get("cat", "")) + " " + str(e.get("gen", ""))).to_lower()
		var ok := true
		for w in ws:
			if not hay.contains(w):
				ok = false
				break
		if ok:
			out.append(id)
	return out


func entry(id: String) -> Dictionary:
	return shapes.get(id, {})


func is_builtin(id: String) -> bool:
	return bool(shapes.get(id, {}).get("builtin", false))


## The key a shape's picture is kept under: its recipe (generator + parameters) - or its mesh file and time.
static func key_of(e: Dictionary) -> String:
	if str(e.get("gen", "")) == "mesh":
		var f := EditTarget.read_path(str(e.get("file", "")))
		return "shapemesh|%s|%d" % [e.get("file", ""), FileAccess.get_modified_time(f) if FileAccess.file_exists(f) else 0]
	return "shape2|%s|%s" % [e.get("gen", ""), JSON.stringify(Shapes.full_params(str(e.get("gen", "")), e.get("params", {})), "", true)]


## The entry's mesh (thread-safe: a worker may call it). Null if it can't be made.
static func mesh_of(e: Dictionary) -> Mesh:
	if str(e.get("gen", "")) == "mesh":
		var f := EditTarget.read_path(str(e.get("file", "")))
		var r = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_IGNORE) if f != "" and (FileAccess.file_exists(f) or ResourceLoader.exists(f)) else null
		return r as Mesh
	return Shapes.make(str(e.get("gen", "")), e.get("params", {}))


func _new_id(name: String) -> String:
	var base := name.strip_edges().to_snake_case().validate_filename().replace(" ", "_")
	if base == "":
		base = "shape"
	var id := base
	var i := 2
	while shapes.has(id) or _mod.has(id):
		id = "%s_%d" % [base, i]
		i += 1
	return id


## A new shape from a generator and its parameters; its id.
func add(name: String, cat: String, gen: String, params: Dictionary) -> String:
	var id := _new_id(name)
	_put(id, {"name": name.strip_edges(), "cat": cat if cat != "" else USER_CAT, "gen": gen, "params": params.duplicate(true)})
	return id


## A new shape from a mesh (its arrays kept in art/shapes/<id>.res - materials left out); its id ("" if it couldn't be written).
func add_mesh(name: String, cat: String, mesh: Mesh) -> String:
	var id := _new_id(name)
	var res := MESH_DIR + id + ".res"
	var m := ArrayMesh.new()
	for s in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var a := mesh.surface_get_arrays(s)
		for k in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			a[k] = null
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	if m.get_surface_count() == 0:
		return ""
	var f := EditTarget.write_path(res)
	DirAccess.make_dir_recursive_absolute(f.get_base_dir())
	if ResourceSaver.save(m, f) != OK:
		return ""
	_put(id, {"name": name.strip_edges(), "cat": cat if cat != "" else USER_CAT, "gen": "mesh", "file": res})
	return id


func rename(id: String, name: String, cat := "") -> void:
	if not shapes.has(id):
		return
	var e: Dictionary = shapes[id].duplicate(true)
	e["name"] = name.strip_edges()
	if cat != "":
		e["cat"] = cat
	_put(id, e)


## Removes a shape (a mesh shape's .res too, if it's this mod's / the game's own new one).
func remove(id: String) -> void:
	if not shapes.has(id):
		return
	var e: Dictionary = shapes[id]
	shapes.erase(id)
	if str(e.get("gen", "")) == "mesh" and not e.get("builtin", false):
		var f := EditTarget.write_path(str(e.get("file", "")))
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	if EditTarget.is_mod():
		var base = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		var in_game: bool = base is Dictionary and (base.get("shapes", {}) as Dictionary).has(id)
		if in_game:
			_mod[id] = {"deleted": true}
		else:
			_mod.erase(id)


func _put(id: String, e: Dictionary) -> void:
	shapes[id] = e
	if EditTarget.is_mod():
		_mod[id] = e.duplicate(true)
	var c := str(e.get("cat", USER_CAT))
	if not c in categories:
		categories.append(c)


## Writes the library where EditTarget says (the game's file, or the mod's merge file). OK or an error.
func save() -> int:
	if not EditTarget.writable():
		return ERR_UNAVAILABLE
	var path := MERGE if EditTarget.is_mod() else FILE
	var data := {"shapes": _mod} if EditTarget.is_mod() else {"version": 1, "categories": categories, "shapes": shapes}
	var f := FileAccess.open(EditTarget.write_path(path), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t") + "\n")
	return OK
