class_name LiveEdits
extends RefCounted
## What the Live Editor changed, kept: the game's world is mostly made in code (a
## town, a station, a creature, an effect...), so there's often no file to save an
## edit into. Each edit is kept against the KIND of thing it was made on - its key
## (key_of: "every Athenian station", "every wolf", "the player") - and the part of
## it changed (a node path under it), and put back each time such a thing is made.
##
## data/live_edits.json (in a mod: its copy, or a .merge of it - Mods):
##   {key: {section: {...}}}  - a section per Live Editor tab ("node", "material",
##   "solids", "fx"...), its data the tab's own (JSON: Variants as var_to_str).
## Each section is a Live Editor tab's: scripts/world/live/tabs/<section>_tab.gd, whose
## `static func apply_edit(anchor: Node, data: Dictionary)` puts it back (loaded only
## when some edit has that section; register() for one that isn't a tab).
##
## Keys: a node with meta "edit_key" is an anchor (builders set it: CosmosTown
## "town/<empire>/<kind>", CosmosStation "station/<empire>"...); else the nearest
## ancestor (or itself) with a script is, keyed by its script's file (or a scene's).
## The anchor's applied when it enters the tree, and again a little later (its parts
## are often built on workers and come in after it).

const FILE := "res://data/live_edits.json"
## Seconds after an anchor enters to put its edits back again (parts built later).
const RETRIES := [0.6, 2.5, 8.0]

static var data := {}             # key -> {section -> data}
static var _loaded := false
static var _appliers := {}         # section -> Callable(anchor: Node, data)
static var _hooked: SceneTree
static var _scripts := {}          # script path -> true (anchors that may have edits)
## Edits made since the last save.
static var dirty := false
## Called before a save (a tab writing what it made: the Model tab's meshes, the Materials tab's pictures).
static var before_save: Array = []


static func load_all() -> void:
	_loaded = true
	data = {}
	var t := FileAccess.get_file_as_string(FILE)
	if t != "":
		var d = JSON.parse_string(t)
		if d is Dictionary:
			data = d
	_index()


static func _index() -> void:
	_scripts.clear()
	for k in data:
		if str(k).begins_with("res://"):
			_scripts[str(k)] = true


## Starts putting the edits back on the things made from now on (Cosmos, as the world's made).
static func hook(tree: SceneTree) -> void:
	if not _loaded:
		load_all()
	if _hooked == tree:
		return
	_hooked = tree
	tree.node_added.connect(_on_node_added)


static func register(section: String, applier: Callable) -> void:
	_appliers[section] = applier


## The kind of thing `n` is part of: [anchor node, its key] ([null, ""] - none).
static func anchor_of(n: Node) -> Array:
	var a := n
	while a:
		if a.has_meta("edit_key"):
			return [a, str(a.get_meta("edit_key"))]
		a = a.get_parent()
	a = n
	while a and a != a.get_tree().root:
		if a.scene_file_path != "":
			return [a, a.scene_file_path]
		var s: Script = a.get_script()
		if s and s.resource_path != "" and not s.resource_path.contains("::"):
			return [a, s.resource_path]
		a = a.get_parent()
	return [null, ""]


## `n`'s path under its anchor ("." - the anchor itself): its names, with the
## engine's made-up ones (@MeshInstance3D@123) as the class and its place among
## its siblings of that class.
static func rel_path(anchor: Node, n: Node) -> String:
	if n == anchor:
		return "."
	var parts := PackedStringArray()
	var a := n
	while a and a != anchor:
		parts.insert(0, _name_of(a))
		a = a.get_parent()
	return "/".join(parts)


static func _name_of(n: Node) -> String:
	if not made_up(n):
		return str(n.name)
	var k := 0
	var p := n.get_parent()
	if p:
		for c in p.get_children():
			if c == n:
				break
			if c.get_class() == n.get_class() and made_up(c):
				k += 1
	return "%s#%d" % [n.get_class(), k]


## `n`'s name is the engine's, not its maker's: "@MeshInstance3D@12", its copy's
## "_MeshInstance3D_12", or the class's own ("MeshInstance3D", "MeshInstance3D2").
static func made_up(n: Node) -> bool:
	var s := str(n.name)
	var cls := n.get_class()
	if s.contains("@"):
		return true
	if s.begins_with("_" + cls + "_") and s.trim_prefix("_" + cls + "_").is_valid_int():
		return true
	return s == cls or (s.begins_with(cls) and s.trim_prefix(cls).is_valid_int())


## The node at `rel` under `anchor` (null - not there, or not yet).
static func find(anchor: Node, rel: String) -> Node:
	if rel == "." or rel == "":
		return anchor
	var n := anchor
	for part in rel.split("/"):
		var next: Node = null
		if part.contains("#"):
			var cls := part.get_slice("#", 0)
			var k := int(part.get_slice("#", 1))
			for c in n.get_children():
				if c.get_class() == cls and made_up(c):
					if k == 0:
						next = c
						break
					k -= 1
		else:
			next = n.get_node_or_null(NodePath(part))
		if next == null:
			return null
		n = next
	return n


## A tab's section for `key` (made empty if new).
static func section(key: String, sec: String) -> Dictionary:
	if not _loaded:
		load_all()
	if not data.has(key):
		data[key] = {}
	if not data[key].has(sec):
		data[key][sec] = {}
	return data[key][sec]


## Records that a section changed (saved later) and indexes the key.
static func touched(key: String) -> void:
	dirty = true
	if key.begins_with("res://"):
		_scripts[key] = true


## Drops a key's section ("" - all of it).
static func forget(key: String, sec := "") -> void:
	if not data.has(key):
		return
	if sec == "":
		data.erase(key)
	else:
		data[key].erase(sec)
		if data[key].is_empty():
			data.erase(key)
	dirty = true
	_index()


## Writes the edits (the game's file, or the mod's - EditTarget): true when written.
static func save() -> bool:
	var et: GDScript = load("res://scripts/editor/edit_target.gd")
	if not et.writable():
		return false
	for cb in before_save:
		(cb as Callable).call()
	var f := FileAccess.open(et.write_path(FILE), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t", true))
	f.close()
	dirty = false
	return true


## Puts the edits for `anchor`'s key back on it, every section.
static func apply(anchor: Node, key := "") -> void:
	if key == "":
		key = str(anchor_of(anchor)[1])
	if not data.has(key) or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return
	for sec in data[key]:
		var f: Callable = _applier(str(sec))
		if f.is_valid():
			f.call(anchor, data[key][sec])


## Section `sec`'s way back: registered, or its tab's static apply_edit.
static func _applier(sec: String) -> Callable:
	if _appliers.has(sec):
		return _appliers[sec]
	var path := "res://scripts/world/live/tabs/%s_tab.gd" % sec
	var f := Callable()
	if ResourceLoader.exists(path):
		var s = load(path)
		if s is GDScript and has_static(s, "apply_edit"):
			f = Callable(s, "apply_edit")
	_appliers[sec] = f
	return f


## Script `s` (compiled) has a function `fn` of its own.
static func has_static(s: GDScript, fn: String) -> bool:
	if s == null or not s.can_instantiate():
		return false
	for m in s.get_script_method_list():
		if m["name"] == fn:
			return true
	return false


static func _on_node_added(n: Node) -> void:
	if data.is_empty():
		return
	var key := ""
	if n.has_meta("edit_key"):
		key = str(n.get_meta("edit_key"))
	elif n.scene_file_path != "" and data.has(n.scene_file_path):
		key = n.scene_file_path
	else:
		var s: Script = n.get_script()
		if s == null or not _scripts.has(s.resource_path):
			return
		key = s.resource_path
	if not data.has(key):
		return
	_later(n, key, 0.0)
	for t in RETRIES:
		_later(n, key, t)


static func _later(n: Node, key: String, t: float) -> void:
	var w: WeakRef = weakref(n)
	var go := func():
		var o = w.get_ref()
		if o:
			apply(o, key)
	if t <= 0.0:
		go.call_deferred()
	else:
		n.get_tree().create_timer(t, false).timeout.connect(go)


## Variants in JSON (vectors, colours, transforms...) and back.
static func enc(v: Variant) -> Variant:
	if v is bool or v is int or v is float or v is String:
		return v
	return {"v": var_to_str(v)}


static func dec(v: Variant) -> Variant:
	if v is Dictionary and v.has("v"):
		return str_to_var(str(v["v"]))
	return v
