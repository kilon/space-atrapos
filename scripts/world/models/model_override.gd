extends RefCounted
## A model's override: the mesh editor saves an edited model (and a character's material table,
## model.json) beside the game's own, in res://art/overrides/ (laid out like res://), and never
## writes over the original. An override has VARIANTS - versions of it, numbered 1, 2, 3... - each a
## folder of its own files:
##   res://art/overrides/art/pirate_3d/pirate.glb.variants/3/pirate.glb   (+ model.json)
## The LATEST (the highest number) is the active one: the game uses it. A file a variant lacks (a
## model.json never edited) is read from the original. No variants: the original is used. (A Blender
## rebuild of a character writes the original: the variants stay.) Read from their own files as the
## game runs (glTF read at run time), so a save shows at once, imported or not.
##   const ModelOverride := preload("res://scripts/world/models/model_override.gd")

const DIR := "res://art/overrides/"

## Where overrides live: DIR (tests point it at a folder of their own - never the game's).
static var dir := DIR

static var _scenes := {}   # variant file -> PackedScene (read once)


## The folder of `model_path`'s variants.
static func root_of(model_path: String) -> String:
	return dir + model_path.trim_prefix("res://") + ".variants/"


## `model_path`'s variants' numbers, oldest first ([] - none: the original is used).
static func variants(model_path: String) -> Array:
	var out := []
	var root := root_of(model_path)
	if not DirAccess.dir_exists_absolute(root):
		return out
	for d in DirAccess.get_directories_at(root):
		if d.is_valid_int() and int(d) > 0:
			out.append(int(d))
	out.sort()
	return out


## The active variant: the latest (0 - none, the original).
static func active(model_path: String) -> int:
	var v := variants(model_path)
	return v[-1] if not v.is_empty() else 0


## `model_path` has an override (a variant).
static func has(model_path: String) -> bool:
	return active(model_path) > 0


## Variant `n`'s file `name` (the model's own file if no name). n = 0: the original's.
static func file_of(model_path: String, n: int, name := "") -> String:
	var f := name if name != "" else model_path.get_file()
	if n <= 0:
		return model_path.get_base_dir().path_join(f)
	return root_of(model_path) + str(n) + "/" + f


## The file to read for `model_path`'s file `name` (the model's own if none) in variant `n` (-1: the
## active one): the variant's if it has it, else the original's.
static func read(model_path: String, name := "", n := -1) -> String:
	if n < 0:
		n = active(model_path)
	var f := file_of(model_path, n, name)
	return f if n > 0 and FileAccess.file_exists(f) else file_of(model_path, 0, name)


## A new variant (the latest - so the active one): a copy of variant `from`'s files (0 - empty: its
## files read from the original till it's saved). Its number.
static func add(model_path: String, from := 0) -> int:
	var v := variants(model_path)
	var n: int = (v[-1] if not v.is_empty() else 0) + 1
	var dir := root_of(model_path) + str(n) + "/"
	DirAccess.make_dir_recursive_absolute(dir)
	if from > 0:
		var src := root_of(model_path) + str(from) + "/"
		for f in DirAccess.get_files_at(src):
			DirAccess.copy_absolute(src + f, dir + f)
	forget(model_path)
	return n


## Variant `n` deleted (the one before it becomes active if it was the latest).
static func erase(model_path: String, n: int) -> void:
	var dir := root_of(model_path) + str(n) + "/"
	if n <= 0 or not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	DirAccess.remove_absolute(dir)
	_prune(root_of(model_path))
	forget(model_path)


## Empty folders left by erasing removed, up to art/overrides/ itself.
static func _prune(folder: String) -> void:
	var top := dir.trim_suffix("/")
	var d := folder.trim_suffix("/")
	while d.length() >= top.length() and DirAccess.dir_exists_absolute(d) \
			and DirAccess.get_files_at(d).is_empty() and DirAccess.get_directories_at(d).is_empty():
		DirAccess.remove_absolute(d)
		if d == top:
			break
		d = d.get_base_dir()


## When variant `n` was last saved (Unix time; 0 - never).
static func saved_at(model_path: String, n: int) -> int:
	var f := file_of(model_path, n)
	return FileAccess.get_modified_time(f) if n > 0 and FileAccess.file_exists(f) else 0


## `model_path` as a scene: its active variant (read as glTF at run time), else the game's own.
static func scene(model_path: String) -> PackedScene:
	var p := read(model_path)
	if p == model_path and not stale(model_path):
		return load(model_path)
	if _scenes.has(p):
		return _scenes[p]
	var ps := build(model_path)
	_scenes[p] = ps
	return ps


## The override's scene read from its file - nothing remembered (safe on a worker: Stage3D.warm reads
## them there; remember() keeps it).
static func build(model_path: String) -> PackedScene:
	var p := read(model_path)
	if p == model_path and not stale(model_path):
		return load(model_path)
	var ps: PackedScene = null
	if p.get_extension().to_lower() in ["glb", "gltf"]:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(p, st) == OK:
			var root := doc.generate_scene(st)
			if root:
				_own(root, root)
				ps = PackedScene.new()
				ps.pack(root)
				root.free()
	if ps == null and ResourceLoader.exists(p):
		ps = load(p)   # (an exported game: the imported override)
	if ps == null:
		ps = load(model_path)
	return ps


## A scene build() made (on a worker) kept as `model_path`'s override.
static func remember(model_path: String, ps: PackedScene) -> void:
	var p := read(model_path)
	if p != model_path and ps != null:
		_scenes[p] = ps


## `model_path`'s variants forgotten (saved again, added, erased): read anew next time.
static func forget(model_path: String) -> void:
	var root := root_of(model_path)
	for k in _scenes.keys():
		if str(k).begins_with(root) or str(k) == model_path:
			_scenes.erase(k)


## The model's own file saved over (the editor's Save) since the game imported it: read as glTF at run time
## till it's imported again - a save shows at once. (An exported game: never - its files can't change.)
static func stale(model_path: String) -> bool:
	if not model_path.get_extension().to_lower() in ["glb", "gltf"] or not FileAccess.file_exists(model_path + ".import"):
		return false
	var cf := ConfigFile.new()
	if cf.load(model_path + ".import") != OK:
		return false
	var imp := str(cf.get_value("remap", "path", ""))
	if imp == "":
		return false
	if not FileAccess.file_exists(imp):
		return true
	return FileAccess.get_modified_time(model_path) > FileAccess.get_modified_time(imp) + 1


static func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)
