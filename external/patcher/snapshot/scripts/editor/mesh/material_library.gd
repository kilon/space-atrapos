extends RefCounted
## The mesh editor's material library (its Materials tab): every material to pick, edit and
## give to a surface, in four groups -
##   "model"     - the open model's own materials (the Material objects themselves);
##   "character" - each character's named materials (art/*_3d/model.json), one entry a name,
##                 knowing which characters use it;
##   "preset"    - the game's looks (MeshIO.PRESETS);
##   "mine"      - your own: data/materials.json.
## Two kinds: "character" - only what the game keeps of a character's material (it merges a
## character into one surface with one shader, reading colour, metal, roughness and glow from
## model.json by the material's name); "standard" - a StandardMaterial3D's main settings and
## its textures. Entries:
##   {id, name, group, kind, values, textures: {slot: res path}, users: [character ids], mat (model only)}
## values: {color: [r,g,b,a], metal, rough, emit, emission: [r,g,b], normal, alpha, uv: [u,v], cull}
## Saved where EditTarget says: the game's data/materials.json ({"version", "materials": {id: entry}}),
## or - in a mod - the mod's data/materials.json.merge (only the mod's changes; a built-in look the
## mod removes: {"deleted": true} under its full id). Pictures picked for a texture are written as
## art/materials/<name>_<slot>.png with the library.

const MeshIO := preload("res://scripts/editor/mesh/mesh_io.gd")
const FILE := "res://data/materials.json"
const MERGE := "res://data/materials.json.merge"
const TEX_DIR := "res://art/materials/"
const GROUPS := ["model", "character", "preset", "mine"]
const GROUP_LABEL := {"model": "This model", "character": "Characters", "preset": "Presets", "mine": "Mine"}
## A texture slot -> its BaseMaterial3D property.
const SLOTS := {"albedo": "albedo_texture", "rough": "roughness_texture", "emission": "emission_texture", "normal": "normal_texture"}
const CULLS := ["back", "front", "none"]

## id -> entry (ids: "model:<instance id>", "char:<name>", "preset:<name>", "mine:<id>")
var entries := {}
## The ids a mod adds, changes or removes (file key -> entry, or {"deleted": true}).
var _mod := {}
## Your materials changed since the last save().
var dirty := false
## Pictures picked this session, written with save(): res path -> Image.
var pending := {}
## Textures by res path (pictures picked this session, and those read).
static var _tex := {}
static var _sphere: Array = []


## Reads the library: the characters' materials, the presets, yours (the mod's changes over the game's).
func load_all() -> void:
	var keep_model := {}
	for id in entries:
		if str(id).begins_with("model:"):
			keep_model[id] = entries[id]
	entries.clear()
	_mod.clear()
	dirty = false
	_load_characters()
	for i in MeshIO.PRESETS.size():
		var p: Array = MeshIO.PRESETS[i]
		var em: Color = p[4]
		var c: Color = p[1]
		entries["preset:" + str(p[0])] = {"id": "preset:" + str(p[0]), "name": str(p[0]), "group": "preset", "kind": "standard", "textures": {}, "users": [],
			"values": _with_defaults({"color": [c.r, c.g, c.b, 1.0], "metal": p[2], "rough": p[3], "emit": p[5], "emission": [em.r, em.g, em.b]})}
	var d = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
	var mine: Dictionary = d.get("materials", {}) if d is Dictionary else {}
	for k in mine:
		_add_mine(str(k), mine[k])
	if EditTarget.is_mod():
		var mf := EditTarget.root() + MERGE.trim_prefix("res://")
		var m = JSON.parse_string(FileAccess.get_file_as_string(mf)) if FileAccess.file_exists(mf) else null
		if m is Dictionary:
			var add: Dictionary = m.get("materials", {})
			for k in add:
				_mod[k] = (add[k] as Dictionary).duplicate(true)
				var full := str(k) if str(k).contains(":") else "mine:" + str(k)
				if add[k].get("deleted", false):
					entries.erase(full)
				else:
					var base: Dictionary = mine.get(k, {})
					_add_mine(str(k), _merge(base, add[k]))
	for id in keep_model:
		entries[id] = keep_model[id]


## Mods' merge: `add`'s keys over `base`'s, dictionaries merged key by key.
static func _merge(base: Variant, add: Variant) -> Variant:
	if base is Dictionary and add is Dictionary:
		var out: Dictionary = base.duplicate()
		for k in add:
			out[k] = _merge(base[k], add[k]) if base.has(k) else add[k]
		return out
	return add


func _add_mine(k: String, e: Dictionary) -> void:
	var kind := "character" if str(e.get("kind", "standard")) == "character" else "standard"
	entries["mine:" + k] = {"id": "mine:" + k, "name": str(e.get("name", k)), "group": "mine", "kind": kind, "users": [],
		"values": _with_defaults(e.get("values", {})), "textures": (e.get("textures", {}) as Dictionary).duplicate()}


## Every character's named materials (its model.json "materials" table) - the outline ink left out.
func _load_characters() -> void:
	var dirs := Array(DirAccess.get_directories_at("res://art/"))
	dirs.sort()
	for dir in dirs:
		if not str(dir).ends_with("_3d"):
			continue
		var who := str(dir).trim_suffix("_3d")
		var src := EditTarget.read_path("res://art/%s/model.json" % dir)
		var d = JSON.parse_string(FileAccess.get_file_as_string(src)) if FileAccess.file_exists(src) else null
		if not d is Dictionary:
			continue
		var table: Dictionary = d.get("materials", {})
		for nm in table:
			var row: Dictionary = table[nm]
			if str(row.get("kind", "")) == "ink" or str(nm).contains("Ink"):
				continue
			var id := "char:" + str(nm)
			if entries.has(id):
				(entries[id]["users"] as Array).append(who)
				continue
			entries[id] = {"id": id, "name": str(nm), "group": "character", "kind": "character", "textures": {}, "users": [who],
				"values": character_values(str(nm), row)}


## A character's material as the game sees it: its colour from the table, its metal, roughness and
## glow from the table if it has them, else from the words in its name (Stage3D.surface_look).
static func character_values(nm: String, row: Dictionary) -> Dictionary:
	var look := Stage3D.surface_look(nm, str(row.get("kind", "toon")))
	var c: Array = row.get("color", [0.8, 0.8, 0.8])
	return _with_defaults({"color": [float(c[0]), float(c[1]), float(c[2]), 1.0], "metal": float(row.get("metal", look["metal"])),
		"rough": float(row.get("rough", look["rough"])), "emit": float(row.get("emit", look["emit"])), "emission": [float(c[0]), float(c[1]), float(c[2])]})


## The recolourable slot a character's material is (by its name: AUT_Armor / AUT_Red / AUT_Glow), or "".
static func slot_of(nm: String) -> String:
	if nm.begins_with("AUT_Armor"):
		return "armour"
	if nm.begins_with("AUT_Red"):
		return "red"
	if nm.begins_with("AUT_Glow"):
		return "glow"
	return ""


static func defaults() -> Dictionary:
	return {"color": [0.8, 0.8, 0.8, 1.0], "metal": 0.0, "rough": 0.6, "emit": 0.0, "emission": [1.0, 1.0, 1.0],
		"normal": 1.0, "alpha": false, "uv": [1.0, 1.0], "cull": "back"}


static func _with_defaults(v: Dictionary) -> Dictionary:
	var out := defaults()
	for k in v:
		out[k] = v[k]
	return out


## The open model's own materials as the "This model" group (`character`: a character's - only
## what the game keeps of them editable).
func set_model(mats: Array, character: bool) -> void:
	for id in entries.keys():
		if str(id).begins_with("model:"):
			entries.erase(id)
	var n := 0
	for m: Material in mats:
		n += 1
		var id := "model:%d" % m.get_instance_id()
		entries[id] = {"id": id, "name": m.resource_name if m.resource_name != "" else "Material %d" % n, "group": "model",
			"kind": "character" if character else "standard", "textures": {}, "users": [], "mat": m}


## The ids of `group` ("": all) whose name, group, kind or users have every word of `words` - in group order.
func ids(group := "", words := "") -> Array:
	var ws := words.to_lower().split(" ", false)
	var out := []
	for g in GROUPS:
		if group != "" and g != group:
			continue
		for id in entries:
			var e: Dictionary = entries[id]
			if e["group"] != g:
				continue
			var hay := ("%s %s %s %s" % [e["name"], GROUP_LABEL[g], e["kind"], " ".join(e.get("users", []))]).to_lower()
			var ok := true
			for w in ws:
				if not hay.contains(w):
					ok = false
					break
			if ok:
				out.append(id)
	return out


func entry(id: String) -> Dictionary:
	return entries.get(id, {})


func has(id: String) -> bool:
	return entries.has(id)


## Its settings can be changed here: yours, and the open model's own (a StandardMaterial3D's kind);
## the built-in looks are kept as they are (duplicate one to change it).
func is_editable(id: String) -> bool:
	var e := entry(id)
	if e.is_empty():
		return false
	if e["group"] == "model":
		return e["mat"] is BaseMaterial3D
	return e["group"] == "mine"


func is_builtin(id: String) -> bool:
	return str(entry(id).get("group", "")) in ["character", "preset"]


## The entry's settings now (a model's material: read from it).
func values(id: String) -> Dictionary:
	var e := entry(id)
	if e.is_empty():
		return defaults()
	if e["group"] == "model":
		return values_of(e["mat"])
	return (e["values"] as Dictionary).duplicate(true)


## The entry's textures: slot -> Texture2D (a model's material: its own).
func textures(id: String) -> Dictionary:
	var e := entry(id)
	var out := {}
	if e.is_empty():
		return out
	if e["group"] == "model":
		var bm := e["mat"] as BaseMaterial3D
		if bm:
			for s in SLOTS:
				var t = bm.get(SLOTS[s])
				if t is Texture2D:
					out[s] = t
		return out
	for s in e["textures"]:
		var t := texture_at(str(e["textures"][s]))
		if t:
			out[s] = t
	return out


## A material's settings (values) read from it.
static func values_of(mat: Material) -> Dictionary:
	var bm := mat as BaseMaterial3D
	if bm == null:
		return defaults()
	var c := bm.albedo_color
	var e := bm.emission
	return {"color": [c.r, c.g, c.b, c.a], "metal": bm.metallic, "rough": bm.roughness,
		"emit": bm.emission_energy_multiplier if bm.emission_enabled else 0.0, "emission": [e.r, e.g, e.b],
		"normal": bm.normal_scale, "alpha": bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED,
		"uv": [bm.uv1_scale.x, bm.uv1_scale.y], "cull": CULLS[clampi(bm.cull_mode, 0, 2)]}


## Puts `values` (and `tex`: slot -> res path or Texture2D; null - the textures left as they are)
## onto `mat`. A character's kind: only colour, metal, roughness and glow (in its own colour).
static func apply(mat: Material, kind: String, values: Dictionary, tex: Variant = null) -> void:
	var bm := mat as BaseMaterial3D
	if bm == null:
		return
	var v := _with_defaults(values)
	var c: Array = v["color"]
	bm.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]) if c.size() > 3 and kind != "character" else 1.0)
	bm.metallic = float(v["metal"])
	bm.roughness = float(v["rough"])
	var e := float(v["emit"])
	bm.emission_energy_multiplier = e
	if kind == "character":
		bm.emission = Color(float(c[0]), float(c[1]), float(c[2]))
		bm.emission_enabled = e > 0.0
		return
	var ec: Array = v["emission"]
	bm.emission = Color(float(ec[0]), float(ec[1]), float(ec[2]))
	bm.normal_scale = float(v["normal"])
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if bool(v["alpha"]) else BaseMaterial3D.TRANSPARENCY_DISABLED
	var uv: Array = v["uv"]
	bm.uv1_scale = Vector3(float(uv[0]), float(uv[1]), 1.0)
	bm.cull_mode = maxi(CULLS.find(str(v["cull"])), 0) as BaseMaterial3D.CullMode
	if tex is Dictionary:
		for s in SLOTS:
			var t = tex.get(s)
			var tx: Texture2D = t if t is Texture2D else (texture_at(str(t)) if t != null and str(t) != "" else null)
			bm.set(SLOTS[s], tx)
	bm.normal_enabled = bm.normal_texture != null
	bm.emission_enabled = e > 0.0 or bm.emission_texture != null


## A new material of the entry's (named as it is - a character's table keeps it by that name).
func make_material(id: String) -> StandardMaterial3D:
	var e := entry(id)
	var m := StandardMaterial3D.new()
	m.resource_name = str(e.get("name", "Material"))
	apply(m, str(e.get("kind", "standard")), values(id), e.get("textures", {}))
	m.set_meta("mat_lib_id", id)
	return m


## The key the entry's picture is kept under: its kind, settings and textures.
func key_of(id: String) -> String:
	var e := entry(id)
	var tex := []
	var t := textures(id)
	for s in t:
		var tx: Texture2D = t[s]
		tex.append("%s=%s" % [s, tx.resource_path if tx.resource_path != "" else str(tx.get_instance_id())])
	return "mat|" + JSON.stringify([e.get("kind", ""), values(id), tex], "", true).md5_text()


## A ball a metre across (its arrays made once, here; the mesh may be made on a worker).
static func sphere_arrays() -> Array:
	if _sphere.is_empty():
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 1.0
		s.radial_segments = 48
		s.rings = 24
		_sphere = s.get_mesh_arrays()
	return _sphere


static func sphere_mesh(arrays: Array, mat: Material) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, mat)
	return m


# --- changes -----------------------------------------------------------------------------

func _new_key(name: String) -> String:
	var base := name.strip_edges().to_snake_case().validate_filename().replace(" ", "_").replace(":", "_")
	if base == "":
		base = "material"
	var k := base
	var i := 2
	while entries.has("mine:" + k) or _mod.has(k):
		k = "%s_%d" % [base, i]
		i += 1
	return k


## A new material of yours; its id.
func add(name: String, kind: String, vals: Dictionary, tex := {}) -> String:
	var k := _new_key(name)
	var id := "mine:" + k
	entries[id] = {"id": id, "name": name.strip_edges(), "group": "mine", "kind": kind, "users": [],
		"values": _with_defaults(vals.duplicate(true)), "textures": tex.duplicate()}
	_changed(id)
	return id


## A copy of any entry as one of yours; its id.
func duplicate_entry(id: String) -> String:
	var e := entry(id)
	if e.is_empty():
		return ""
	var tex := {}
	if e["group"] != "model":
		tex = (e["textures"] as Dictionary).duplicate()
	return add(str(e["name"]) + " copy", str(e["kind"]), values(id), tex)


func rename(id: String, name: String) -> void:
	if entry(id).get("group", "") != "mine" or name.strip_edges() == "":
		return
	entries[id]["name"] = name.strip_edges()
	_changed(id)


func set_values(id: String, vals: Dictionary) -> void:
	if entry(id).get("group", "") != "mine":
		return
	entries[id]["values"] = _with_defaults(vals.duplicate(true))
	_changed(id)


func set_textures(id: String, tex: Dictionary) -> void:
	if entry(id).get("group", "") != "mine":
		return
	entries[id]["textures"] = tex.duplicate()
	_changed(id)


## Removes an entry: yours - gone; a built-in look - only in a mod (its merge file says so).
## False if it can't be removed here.
func remove(id: String) -> bool:
	var e := entry(id)
	if e.is_empty() or e["group"] == "model":
		return false
	if e["group"] != "mine":
		if not EditTarget.is_mod():
			return false
		_mod[id] = {"deleted": true}
		entries.erase(id)
		dirty = true
		return true
	var k := id.trim_prefix("mine:")
	entries.erase(id)
	if EditTarget.is_mod():
		var base = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
		if base is Dictionary and (base.get("materials", {}) as Dictionary).has(k):
			_mod[k] = {"deleted": true}
		else:
			_mod.erase(k)
	dirty = true
	return true


func _changed(id: String) -> void:
	dirty = true
	if EditTarget.is_mod() and id.begins_with("mine:"):
		_mod[id.trim_prefix("mine:")] = _saved(entries[id])


static func _saved(e: Dictionary) -> Dictionary:
	return {"name": e["name"], "kind": e["kind"], "values": e["values"].duplicate(true), "textures": e["textures"].duplicate()}


## Where a picture picked for entry `id`'s texture `slot` is kept.
func texture_path(id: String, slot: String) -> String:
	var nm := str(entry(id).get("name", "material")).to_snake_case().validate_filename().replace(" ", "_")
	return TEX_DIR + "%s_%s.png" % [nm, slot]


## A picture picked for `res_path` this session (written with save()).
func keep_picture(res_path: String, img: Image) -> Texture2D:
	pending[res_path] = img
	var t := ImageTexture.create_from_image(img)
	_tex[res_path] = t
	return t


## Writes the library where EditTarget says (the game's file, or the mod's merge file) - and the
## pictures picked. OK or an error.
func save() -> int:
	if not EditTarget.writable():
		return ERR_UNAVAILABLE
	for p in pending:
		var to := EditTarget.write_path(p)
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		(pending[p] as Image).save_png(to)
	pending.clear()
	var data := {}
	if EditTarget.is_mod():
		data = {"materials": _mod}
	else:
		var mine := {}
		for id in entries:
			if entries[id]["group"] == "mine":
				mine[str(id).trim_prefix("mine:")] = _saved(entries[id])
		data = {"version": 1, "materials": mine}
	var path := MERGE if EditTarget.is_mod() else FILE
	var f := FileAccess.open(EditTarget.write_path(path), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t") + "\n")
	f.close()
	dirty = false
	return OK


## The texture at `path` (a picture picked this session, the game's imported one, or the mod's file).
static func texture_at(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex.has(path):
		return _tex[path]
	var p := EditTarget.read_path(path)
	var t: Texture2D = null
	if not p.begins_with("user://") and ResourceLoader.exists(p):
		t = load(p) as Texture2D
	if t == null and FileAccess.file_exists(p):
		var img := Image.load_from_file(ProjectSettings.globalize_path(p))
		if img:
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	_tex[path] = t
	return t
