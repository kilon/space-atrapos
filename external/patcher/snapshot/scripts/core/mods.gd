extends Node
## Mods: your changes to the game, any of it - its data, scripts, scenes, shaders,
## models, pictures, sounds, fonts - kept apart from it and laid over it as it
## starts. The first autoload: the mods are in place before anything else of the
## game loads.
##
## A mod is a folder, user://mods/<id>/:
##   mod.json   {id, name, version, author, description, main}   (main: a script of the
##              mod's, "res://..." - run once the game's up: a Node added to the root)
##   files/     laid out like the game (files/data/galaxy.json is res://data/galaxy.json):
##              a file the game has replaces it, a new one is added.
##              <file>.merge (a JSON object) is merged into the game's JSON file of that
##              name (dictionaries key by key, deep; other values replaced) - a mod
##              changing a few entries of a big data file without copying all of it.
## Turned on, in order (a later mod wins): user://mods/mods.cfg. Changes apply at the
## next start (restart()).
##
## How: every mod's files (and the merged JSON) go into one zip mounted over res://
## (ProjectSettings.load_resource_pack) - what the game reads as files (JSON, text)
## and lists (DirAccess) - and a resource loader in front of Godot's own (Loader)
## loads what the game load()s from the mod's own files: scripts and scenes from their
## text, pictures, models, sounds and fonts from their raw files (an exported game
## knows only its own imported copies).
##
## Safety: a start that never reached the title screen (a mod breaking it) leaves
## a mark; the next start runs without mods (safe_mode) and says so. `--no-mods`
## starts without them too.

const DIR := "user://mods/"
const CONFIG := "user://mods/mods.cfg"
const CACHE := "user://mods/.cache/"
const BOOTING := "user://mods/.cache/booting"
const FILES := "files/"
## Loaded from the mod's own file by Loader (Godot's loader would load the game's import).
const FRONT := ["gd", "tscn", "scn", "tres", "res", "gdshader", "gdshaderinc", "png", "jpg", "jpeg", "webp", "svg",
	"bmp", "tga", "glb", "gltf", "ogg", "wav", "mp3", "ttf", "otf", "woff", "woff2"]
const TYPES := {"gd": "GDScript", "tscn": "PackedScene", "scn": "PackedScene", "tres": "Resource", "res": "Resource",
	"gdshader": "Shader", "gdshaderinc": "ShaderInclude", "glb": "PackedScene", "gltf": "PackedScene",
	"ogg": "AudioStreamOggVorbis", "wav": "AudioStreamWAV", "mp3": "AudioStreamMP3",
	"ttf": "FontFile", "otf": "FontFile", "woff": "FontFile", "woff2": "FontFile"}

## The mods running (in order): their mod.json, with "dir".
var active: Array = []
## res:// path -> the mod file that replaces / adds it (the last mod's).
var files := {}
## res:// path -> the mod ids touching it (in order) - two mods on one file shown in the Mods screen.
var touched := {}
## Problems met loading them (shown in the Mods screen).
var errors: PackedStringArray = []
## This start runs without mods: the last start with them never reached the title screen.
var safe_mode := false
## The mods' main scripts' nodes (or objects), by mod id.
var mains := {}
var _loader: Loader


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE)
	if "--no-mods" in OS.get_cmdline_user_args() or "--no-mods" in OS.get_cmdline_args():
		return
	var ids := enabled()
	if ids.is_empty():
		return
	if FileAccess.file_exists(BOOTING):
		safe_mode = true
		DirAccess.remove_absolute(BOOTING)
		errors.append("The last start with mods didn't reach the title screen: started without them. Turn them on again in Mods.")
		return
	var f := FileAccess.open(BOOTING, FileAccess.WRITE)
	if f:
		f.store_string(",".join(ids))
		f.close()
	_mount(ids)


func _ready() -> void:
	if active.is_empty():
		return
	# (after every autoload's _ready: the game's up - each mod's own script runs)
	_run_mains.call_deferred()


## The title screen's up: this start with mods worked (main_menu calls it).
func started() -> void:
	if FileAccess.file_exists(BOOTING):
		DirAccess.remove_absolute(BOOTING)


# --- The mods installed ----------------------------------------------------------

## Every mod in user://mods/: its mod.json (with "dir", "enabled"), in load order
## (the turned-on ones first, in theirs; then the rest by name).
func installed() -> Array:
	var on := enabled()
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for id in d.get_directories():
		if id.begins_with("."):
			continue
		var m := info(id)
		if m.is_empty():
			continue
		m["enabled"] = id in on
		out.append(m)
	out.sort_custom(func(a, b):
		var ia := on.find(a["id"])
		var ib := on.find(b["id"])
		if ia >= 0 and ib >= 0:
			return ia < ib
		if (ia >= 0) != (ib >= 0):
			return ia >= 0
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return out


## A mod's mod.json (with "dir", "id"), or {} when it isn't one.
func info(id: String) -> Dictionary:
	var path := DIR + id + "/mod.json"
	if not FileAccess.file_exists(path):
		return {}
	var m = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not m is Dictionary:
		m = {"name": id, "broken": "mod.json isn't valid JSON"}
	m["id"] = id
	m["dir"] = DIR + id + "/"
	for k in ["name", "version", "author", "description", "main"]:
		if not m.has(k):
			m[k] = id if k == "name" else ""
	return m


func save_info(m: Dictionary) -> void:
	var out := m.duplicate()
	for k in ["dir", "enabled", "broken"]:
		out.erase(k)
	var f := FileAccess.open(DIR + str(m["id"]) + "/mod.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "\t"))


## The turned-on mods' ids, in load order.
func enabled() -> PackedStringArray:
	var c := ConfigFile.new()
	if c.load(CONFIG) != OK:
		return PackedStringArray()
	var out := PackedStringArray()
	for id in c.get_value("mods", "enabled", []):
		if DirAccess.dir_exists_absolute(DIR + str(id)):
			out.append(str(id))
	return out


func set_enabled_list(ids: PackedStringArray) -> void:
	var c := ConfigFile.new()
	c.load(CONFIG)
	c.set_value("mods", "enabled", Array(ids))
	c.save(CONFIG)


func set_enabled(id: String, on: bool) -> void:
	var ids := enabled()
	if on and not id in ids:
		ids.append(id)
	elif not on and id in ids:
		ids.remove_at(ids.find(id))
	set_enabled_list(ids)


## Moves a turned-on mod `d` places in the load order (later wins).
func move(id: String, d: int) -> void:
	var ids := enabled()
	var i := ids.find(id)
	if i < 0:
		return
	var j := clampi(i + d, 0, ids.size() - 1)
	ids.remove_at(i)
	ids.insert(j, id)
	set_enabled_list(ids)


## The mods to run differ from the ones running: a restart applies them.
func needs_restart() -> bool:
	var now := PackedStringArray()
	for m in active:
		now.append(str(m["id"]))
	return now != enabled()


## A new, empty mod: its id (from `name`, made unique).
func create(name: String, author := "") -> String:
	var base := name.to_snake_case().replace(" ", "_").validate_filename()
	base = base.replace(".", "_")
	if base == "":
		base = "mod"
	var id := base
	var n := 2
	while DirAccess.dir_exists_absolute(DIR + id):
		id = "%s_%d" % [base, n]
		n += 1
	DirAccess.make_dir_recursive_absolute(DIR + id + "/" + FILES)
	save_info({"id": id, "name": name, "version": "1.0", "author": author, "description": "", "main": ""})
	return id


## Deletes a mod's folder (and turns it off).
func remove(id: String) -> void:
	set_enabled(id, false)
	_rm_tree(DIR + id)


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


## The folder of a mod's game files (res://x is <this>x).
func files_dir(id: String) -> String:
	return DIR + id + "/" + FILES


## A mod's files: res:// paths, sorted (merges as "<path>.merge").
func mod_files(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	_walk(files_dir(id), "", out)
	out.sort()
	return out


func _walk(base: String, rel: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(base + rel)
	if d == null:
		return
	d.include_hidden = false
	for f in d.get_files():
		out.append("res://" + rel + f)
	for sub in d.get_directories():
		_walk(base, rel + sub + "/", out)


## Packs a mod into a zip (mod.json + files/) to share: true when written.
func export_zip(id: String, to: String) -> bool:
	var z := ZIPPacker.new()
	if z.open(to) != OK:
		return false
	var root := DIR + id + "/"
	var all := PackedStringArray()
	_walk(root, "", all)
	for p in all:
		var rel := p.trim_prefix("res://")
		z.start_file(id + "/" + rel)
		z.write_file(FileAccess.get_file_as_bytes(root + rel))
		z.close_file()
	z.close()
	return true


## Installs a mod from a zip (one made by export_zip: <id>/mod.json ...; or mod.json
## at its root): its id, or "" (and why in `errors`).
func install_zip(path: String) -> String:
	var z := ZIPReader.new()
	if z.open(path) != OK:
		errors.append("Can't open %s" % path)
		return ""
	var names := z.get_files()
	var prefix := ""
	for n in names:
		if n.get_file() == "mod.json" and n.count("/") <= 1:
			prefix = n.get_base_dir()
			break
	if not (prefix + "/mod.json").trim_prefix("/") in names:
		errors.append("%s has no mod.json" % path.get_file())
		z.close()
		return ""
	var m = JSON.parse_string(z.read_file((prefix + "/mod.json").trim_prefix("/")).get_string_from_utf8())
	var id := str(m.get("id", prefix if prefix != "" else path.get_file().get_basename())) if m is Dictionary else path.get_file().get_basename()
	id = id.validate_filename().replace(".", "_")
	_rm_tree(DIR + id)
	for n in names:
		if n.ends_with("/") or (prefix != "" and not n.begins_with(prefix + "/")):
			continue
		var rel := n.trim_prefix(prefix + "/") if prefix != "" else n
		if rel.contains(".."):
			continue   # (nothing written outside the mod's folder)
		var to := DIR + id + "/" + rel
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		var f := FileAccess.open(to, FileAccess.WRITE)
		if f:
			f.store_buffer(z.read_file(n))
	z.close()
	return id


## Restarts the game (the mods turned on now load).
func restart() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("location.reload()")
		return
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()


# --- Laying the mods over the game -------------------------------------------------

func _mount(ids: PackedStringArray) -> void:
	var merges := {}   # res path -> [mod file...]
	for id in ids:
		var m := info(id)
		if m.is_empty():
			errors.append("%s: no mod.json - left out" % id)
			continue
		if m.has("broken"):
			errors.append("%s: %s - left out" % [id, m["broken"]])
			continue
		active.append(m)
		for p in mod_files(id):
			var src := files_dir(id) + p.trim_prefix("res://")
			if p.ends_with(".merge"):
				var target := p.trim_suffix(".merge")
				if not merges.has(target):
					merges[target] = []
				merges[target].append(src)
				_touch(target, id)
				continue
			files[p] = src
			_touch(p, id)
	if active.is_empty():
		return
	# The zip: built again only when a mod's files changed (their names, sizes and times).
	var sig := PackedStringArray()
	for p in files:
		sig.append("%s|%d|%d" % [files[p], FileAccess.get_size(files[p]), FileAccess.get_modified_time(files[p])])
	for p in merges:
		for src in merges[p]:
			sig.append("%s|%d" % [src, FileAccess.get_modified_time(src)])
	sig.sort()
	var key := str(hash(";".join(sig)))
	var zip := CACHE + "active.zip"
	var old := FileAccess.get_file_as_string(CACHE + "active.key")
	if old != key or not FileAccess.file_exists(zip):
		var merged := {}
		for target in merges:   # (from the game's file - or a mod's that replaces it - before the zip's mounted)
			var base_text := FileAccess.get_file_as_string(files[target]) if files.has(target) else FileAccess.get_file_as_string(target)
			var base = JSON.parse_string(base_text) if base_text != "" else {}
			if base == null:
				base = {}
			for src in merges[target]:
				var add = JSON.parse_string(FileAccess.get_file_as_string(src))
				if add == null:
					errors.append("%s: not valid JSON - not merged" % src.trim_prefix(DIR))
					continue
				base = merge(base, add)
			merged[target] = JSON.stringify(base, "\t").to_utf8_buffer()
		var z := ZIPPacker.new()
		if z.open(zip) != OK:
			errors.append("Can't write %s" % zip)
			return
		for p in files:
			if merged.has(p):
				continue
			z.start_file(p.trim_prefix("res://"))
			z.write_file(FileAccess.get_file_as_bytes(files[p]))
			z.close_file()
		for p in merged:
			z.start_file(p.trim_prefix("res://"))
			z.write_file(merged[p])
			z.close_file()
		z.close()
		var kf := FileAccess.open(CACHE + "active.key", FileAccess.WRITE)
		if kf:
			kf.store_string(key)
	if not ProjectSettings.load_resource_pack(zip, true):
		errors.append("Couldn't mount the mods' files")
		return
	_loader = Loader.new()
	for p in files:
		if str(p.get_extension()).to_lower() in FRONT:
			_loader.over[p] = files[p]
	for p in merges:   # (a merged .tres / .json loaded with load(): from the zip, as the game's own path)
		_loader.over.erase(p)
	ResourceLoader.add_resource_format_loader(_loader, true)


func _touch(p: String, id: String) -> void:
	if not touched.has(p):
		touched[p] = []
	if not id in touched[p]:
		touched[p].append(id)


## `add` merged into `base`: dictionaries key by key (deep), anything else replaced.
static func merge(base: Variant, add: Variant) -> Variant:
	if base is Dictionary and add is Dictionary:
		var out: Dictionary = base.duplicate()
		for k in add:
			out[k] = merge(base[k], add[k]) if base.has(k) else add[k]
		return out
	return add


func _run_mains() -> void:
	for m in active:
		var main := str(m.get("main", ""))
		if main == "":
			continue
		if not main.begins_with("res://"):
			main = "res://" + main
		var s = load(main)
		if not s is Script or not (s as Script).can_instantiate():
			errors.append("%s: its main script %s doesn't load" % [m["id"], main])
			continue
		var o = s.new()
		mains[m["id"]] = o
		if o is Node:
			o.name = "Mod_" + str(m["id"])
			get_tree().root.add_child(o)


## Godot's loader for the mods' files, in front of its own: a path a mod replaces or
## adds is loaded from the mod's file.
class Loader extends ResourceFormatLoader:
	var over := {}   # res path -> mod file

	func _get_recognized_extensions() -> PackedStringArray:
		return PackedStringArray(FRONT)

	func _recognize_path(path: String, _type: StringName) -> bool:
		return over.has(path)

	func _handles_type(_type: StringName) -> bool:
		return true

	func _get_resource_type(path: String) -> String:
		if not over.has(path):
			return ""
		var ext := path.get_extension().to_lower()
		if ext in ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga"]:
			return "ImageTexture"
		return str(TYPES.get(ext, "Resource"))

	func _exists(path: String) -> bool:
		return over.has(path)

	func _load(path: String, _original: String, _sub: bool, _cache: int) -> Variant:
		var src: String = over[path]
		var ext := path.get_extension().to_lower()
		match ext:
			"gd":
				var s := GDScript.new()
				s.source_code = FileAccess.get_file_as_string(src)
				var err := s.reload()
				if err != OK:
					push_error("Mod script %s doesn't compile (%s)" % [path, error_string(err)])
				return s
			"png", "jpg", "jpeg", "webp", "bmp", "tga", "svg":
				var img := Image.new()
				var err := img.load_svg_from_string(FileAccess.get_file_as_string(src)) if ext == "svg" else img.load(src)
				if err != OK:
					return err
				img.generate_mipmaps()
				return ImageTexture.create_from_image(img)
			"glb", "gltf":
				var doc := GLTFDocument.new()
				var st := GLTFState.new()
				var err := doc.append_from_file(src, st)
				if err != OK:
					return err
				var root := doc.generate_scene(st)
				var ps := PackedScene.new()
				_own(root, root)
				ps.pack(root)
				root.free()
				return ps
			"ogg":
				return AudioStreamOggVorbis.load_from_file(src)
			"wav":
				return AudioStreamWAV.load_from_file(src)
			"mp3":
				var mp := AudioStreamMP3.new()
				mp.data = FileAccess.get_file_as_bytes(src)
				return mp
			"ttf", "otf", "woff", "woff2":
				var font := FontFile.new()
				font.load_dynamic_font(src)
				return font
		return ResourceLoader.load(src, "", ResourceLoader.CACHE_MODE_IGNORE)

	## (a generated scene's nodes owned by its root, so pack() keeps them)
	func _own(n: Node, root: Node) -> void:
		for c in n.get_children():
			c.owner = root
			_own(c, root)
