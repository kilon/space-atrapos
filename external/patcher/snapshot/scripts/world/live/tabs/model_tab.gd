extends VBoxContainer
## The Live Editor's Model tab: the meshes of what's picked - each opened in the
## mesh editor (a window over the running game: a copy of it, its edits put back
## with "Put in the world"), or replaced with a model file of yours. The new mesh
## goes on every thing of that kind at once; kept (LiveEdits, section "model":
## {rel path: res path of the mesh}), the mesh saved as a resource
## (res://art/live/<kind>/<part>.res - in the game, or the mod) when the edits are.

const TITLE := "Model"
const ICON := "mesh"
const DIR := "res://art/live/"

## Meshes made this session, not yet written: res path -> Mesh.
static var pending := {}
static var _cache := {}         # res path -> Mesh (loaded once, shared)
static var _hooked := false

var ed: Node
var _list: VBoxContainer
var _dialog: FileDialog


static func handles(n: Node) -> bool:
	return n is MeshInstance3D or not n.find_children("*", "MeshInstance3D", true, false).is_empty()


func bind(e: Node) -> void:
	ed = e
	_hook_save()
	add_child(LiveFields.head("ITS MESHES"))
	_list = VBoxContainer.new()
	add_child(_list)
	var meshes: Array = [ed.selected] if ed.selected is MeshInstance3D else ed.selected.find_children("*", "MeshInstance3D", true, false).slice(0, 24)
	for mi in meshes:
		_list.add_child(_row(mi))


func unbind() -> void:
	ed = null


func _row(mi: MeshInstance3D) -> Control:
	var v := VBoxContainer.new()
	var m := mi.mesh
	var nv := 0
	if m is ArrayMesh:
		for s in m.get_surface_count():
			nv += (m as ArrayMesh).surface_get_array_len(s)
	v.add_child(UI.label("%s  ·  %d vertices, %d surface%s" % [LiveEditor._name_of(mi), nv, m.get_surface_count() if m else 0,
		"" if m and m.get_surface_count() == 1 else "s"], 14))
	var h := HBoxContainer.new()
	var edit := UI.button("Mesh editor", func(): edit_in_window(mi), 14)
	EditorIcons.dress(edit, "mesh", EditorIcons.tip("Mesh editor", "", "Opens a copy of this mesh in the mesh editor, over the running game; \"Put in the world\" there puts it on every one of its kind."))
	edit.text = "Mesh editor"
	h.add_child(edit)
	if not OS.has_feature("web"):
		var rep := UI.button("Replace", func(): _replace(mi), 14)
		EditorIcons.dress(rep, "open", EditorIcons.tip("Replace", "", "Replaces the mesh with a model file of yours (.glb, .gltf, .obj)."))
		rep.text = "Replace"
		h.add_child(rep)
	var back := UI.button("As made", func(): _revert(mi), 14)
	EditorIcons.dress(back, "undo", EditorIcons.tip("As made", "", "Puts back the mesh it was made with (and forgets the kept one)."))
	back.text = "As made"
	h.add_child(back)
	v.add_child(h)
	return v


## The mesh as an ArrayMesh (a primitive's arrays; an ArrayMesh copied).
static func editable(m: Mesh) -> ArrayMesh:
	if m is ArrayMesh:
		return (m as ArrayMesh).duplicate(true)
	var out := ArrayMesh.new()
	if m is PrimitiveMesh:
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (m as PrimitiveMesh).get_mesh_arrays())
		out.surface_set_material(0, (m as PrimitiveMesh).material)
	return out


func edit_in_window(mi: MeshInstance3D) -> void:
	var root := Node3D.new()
	root.name = "Model"
	var part := MeshInstance3D.new()
	part.name = str(mi.name) if not str(mi.name).contains("@") else "Part"
	part.mesh = editable(mi.mesh)
	root.add_child(part)
	var target: WeakRef = weakref(mi)
	var t: Node = ed.open_tool("mesh", "Mesh: " + LiveEditor._name_of(mi), [
		["Put in the world", "apply", "Puts the edited mesh on this - and every one of its kind - now (kept once you save the Live Editor's edits).",
			func(tool: Node):
				if tool.get("mode") == "edit":
					tool.toggle_edit()   # (the edit session finished into the part)
				var ps: Array = tool.parts()
				var o = target.get_ref()
				if ps.is_empty() or o == null:
					return
				put(o, tool.mirrored_mesh(ps[0]))
				tool.set("dirty", false)],
	])
	t._set_model(root, "")
	ed.say("Editing a copy of its mesh: \"Put in the world\" when it's right.")


## Mesh `m` on `mi` and on every one of its kind; kept.
func put(mi: MeshInstance3D, m: Mesh) -> void:
	if not mi.has_meta("live_made_mesh"):
		mi.set_meta("live_made_mesh", mi.mesh)
	mi.mesh = m
	if ed == null or ed.key == "" or ed.anchor == null:
		return
	var rel := LiveEdits.rel_path(ed.anchor, mi)
	var path := DIR + _safe(ed.key) + "/" + _safe(rel) + ".res"
	pending[path] = m
	_cache[path] = m
	LiveEdits.section(ed.key, "model")[rel] = path
	ed.edited("model")
	ed.say("The new mesh is on every %s." % LiveEditor.kind_name(ed.key).trim_prefix("every "))


func _revert(mi: MeshInstance3D) -> void:
	if mi.has_meta("live_made_mesh"):
		mi.mesh = mi.get_meta("live_made_mesh")
	if ed and ed.key != "" and ed.anchor:
		var sec := LiveEdits.section(ed.key, "model")
		sec.erase(LiveEdits.rel_path(ed.anchor, mi))
		ed.edited("model")
	ed.say("As made (others of its kind: the next time they're made).")


func _replace(mi: MeshInstance3D) -> void:
	if _dialog:
		_dialog.queue_free()
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.glb, *.gltf, *.obj ; Models"])
	_dialog.use_native_dialog = true
	add_child(_dialog)
	_dialog.file_selected.connect(func(path: String):
		var MeshIO: GDScript = load("res://scripts/editor/mesh/mesh_io.gd")
		var root: Node3D = MeshIO.read(path)
		if root == null:
			ed.say("Couldn't read " + path.get_file())
			return
		var parts := root.find_children("*", "MeshInstance3D", true, false)
		if parts.is_empty():
			ed.say(path.get_file() + " has no mesh.")
		else:
			put(mi, (parts[0] as MeshInstance3D).mesh)
		root.free())
	_dialog.popup_centered(Vector2i(900, 600))


static func _safe(s: String) -> String:
	return s.trim_prefix("res://").replace("/", "_").replace(".", "_").replace("#", "_").validate_filename()


## The meshes made this session written (with the Live Editor's Save).
static func flush() -> void:
	var et: GDScript = load("res://scripts/editor/edit_target.gd")
	for path in pending:
		var to: String = et.write_path(path)
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		ResourceSaver.save(pending[path], to)
	pending.clear()


static func _hook_save() -> void:
	if not _hooked:
		_hooked = true
		LiveEdits.before_save.append(flush)


static func mesh_at(path: String) -> Mesh:
	if _cache.has(path):
		return _cache[path]
	var et: GDScript = load("res://scripts/editor/edit_target.gd")
	var p: String = et.read_path(path)
	var m = ResourceLoader.load(p) if ResourceLoader.exists(p) or FileAccess.file_exists(p) else null
	_cache[path] = m
	return m


static func apply_edit(anchor: Node, data: Dictionary) -> void:
	for rel in data:
		var mi := LiveEdits.find(anchor, str(rel)) as MeshInstance3D
		if mi == null:
			continue
		var m := mesh_at(str(data[rel]))
		if m and mi.mesh != m:
			if not mi.has_meta("live_made_mesh"):
				mi.set_meta("live_made_mesh", mi.mesh)
			mi.mesh = m
