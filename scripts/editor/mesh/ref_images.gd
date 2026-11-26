extends Node
## The mesh editor's reference images (a node of the editor, `ed`): pictures from anywhere on
## disk (png / jpg / webp) shown in the 3D view to model from - each lined up with a view (front,
## side, top - upright in it, centred on the origin) or on a free plane in the scene, behind the
## model or over it (see-through), with its opacity, size, offset and visibility. The REFERENCE
## IMAGES panel (build_right) adds, picks, changes and removes them; they're kept per model (by its
## path) in user://mesh_ref_images.json and come back when the model's opened again.
## Cheap to draw: each one quad (a shared 1 x 1 mesh, scaled) with an unshaded material - behind
## (a view's): pushed to the far plane in its vertex shader, not writing depth (the model, the grid
## and the overlays all draw over it); over: no depth test, drawn before the edit overlays; a view's
## image fades out as the camera turns away from that view. Pictures are read on a worker.

const FILE := "user://mesh_ref_images.json"
const VIEWS := ["front", "side", "top", "free"]
const VIEW_NAMES := ["Front", "Side", "Top", "Free plane"]
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled/*NODEPTH*/;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float opacity = 1.0;
uniform bool far = false;
uniform bool fade = true;
void vertex() {
	// (POSITION written in any branch: Godot leaves it to us in all - so always set)
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (far) {   // (at the far plane: behind everything drawn)
		POSITION.z = POSITION.w * 0.000001;
	}
}
void fragment() {
	vec4 c = texture(tex, UV);
	float a = c.a * opacity;
	if (fade) {   // (a view's picture: only while that view is looked along)
		a *= smoothstep(0.45, 0.8, abs(dot(normalize(NORMAL), VIEW)));
	}
	ALBEDO = c.rgb;
	ALPHA = a;
}
"""

static var _shaders := {}   # depth tested (false) / not (true) -> Shader
static var _quad: QuadMesh

var ed: Control
## The open model's images: {file, view, layer ("back" / "front"), opacity, height (m), x, y, z,
## turn, tilt (degrees - a free plane's), shown} - and while open "_mi" (its quad), "_tex", "_aspect".
var images: Array = []
var _key := ""
var _root: Node3D
var _tasks: Array = []      # [task id, [Image], entry]
var _save_due := false
var _sel := -1
# the panel
var _list: ItemList
var _fields := {}
var _detail: Control
var _eye: Button
var _remove: Button


func setup(editor: Control) -> void:
	ed = editor
	name = "RefImages"
	set_process(false)


func _exit_tree() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t[0])
	_tasks.clear()
	if _save_due:
		_save_now()


# --- the model's images -----------------------------------------------------------

static func _key_of(path: String) -> String:
	return path if path != "" else "(new model)"


## A model was opened (or made new): its images back.
func model_opened(path: String) -> void:
	if _save_due:
		_save_now()
	for e in images:
		_drop(e)
	images = []
	_key = _key_of(path)
	_sel = -1
	var all := _read_all()
	for d in all.get(_key, []):
		if d is Dictionary and str(d.get("file", "")) != "":
			var e := _defaults(str(d["file"]))
			for k in e:
				if d.has(k):
					e[k] = d[k]
			images.append(e)
			_load(e)
	_fill_list()


static func _defaults(file: String) -> Dictionary:
	return {"file": file, "view": "front", "layer": "back", "opacity": 0.8, "height": 2.0, "x": 0.0, "y": 1.0, "z": 0.0,
		"turn": 0.0, "tilt": 0.0, "shown": true}


## Adds the picture at `file` (any path on disk) - lined up with the front view, behind the model.
## Its index.
func add_file(file: String) -> int:
	var e := _defaults(file)
	images.append(e)
	_load(e)
	_sel = images.size() - 1
	_fill_list()
	_save_soon()
	return _sel


func remove(i: int) -> void:
	if i < 0 or i >= images.size():
		return
	_drop(images[i])
	images.remove_at(i)
	_sel = mini(_sel, images.size() - 1)
	_fill_list()
	_save_soon()
	_request()


## Image `i`'s `key` set to `value` (one of the saved keys), shown at once.
func set_value(i: int, key: String, value) -> void:
	if i < 0 or i >= images.size():
		return
	var e: Dictionary = images[i]
	e[key] = value
	_place(e)
	_save_soon()
	if key in ["shown", "view", "layer"]:
		_fill_list()


## The quad showing image `i` (null: its picture's not read yet, or couldn't be).
func quad_of(i: int) -> MeshInstance3D:
	return images[i].get("_mi") if i >= 0 and i < images.size() else null


## Pictures still being read.
func busy() -> bool:
	return not _tasks.is_empty()


func _load(e: Dictionary) -> void:
	var holder := [null]
	var f: String = e["file"]
	var id := WorkerThreadPool.add_task(func():
		var img: Image = _read_image(f)
		if img and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img.generate_mipmaps()
			holder[0] = img, false, "Reference image")
	_tasks.append([id, holder, e])
	set_process(true)


## The picture at `f` (null: not there, gone meanwhile, or not a picture) - read as bytes first, so a
## file removed while it's read is just missing, not an error.
static func _read_image(f: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) else PackedByteArray()
	if bytes.is_empty():
		return null
	var img := Image.new()
	var ext := f.get_extension().to_lower()
	var err := ERR_FILE_UNRECOGNIZED
	match ext:
		"png":
			err = img.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			err = img.load_jpg_from_buffer(bytes)
		"webp":
			err = img.load_webp_from_buffer(bytes)
		"bmp":
			err = img.load_bmp_from_buffer(bytes)
		"tga":
			err = img.load_tga_from_buffer(bytes)
		_:
			return Image.load_from_file(f)
	return img if err == OK else null


func _process(_dt: float) -> void:
	var left := []
	for t in _tasks:
		if not WorkerThreadPool.is_task_completed(t[0]):
			left.append(t)
			continue
		WorkerThreadPool.wait_for_task_completion(t[0])
		var e: Dictionary = t[2]
		if not images.has(e):
			continue   # (removed, or another model opened)
		var img: Image = t[1][0]
		if img == null:
			ed._say("Couldn't read the reference image %s." % str(e["file"]))
			continue
		e["_tex"] = ImageTexture.create_from_image(img)
		e["_aspect"] = float(img.get_width()) / maxf(1.0, img.get_height())
		_place(e)
	_tasks = left
	if _tasks.is_empty():
		set_process(false)


static func _shader(no_depth: bool) -> Shader:
	if not _shaders.has(no_depth):
		var s := Shader.new()
		s.code = SHADER.replace("/*NODEPTH*/", ", depth_test_disabled" if no_depth else "")
		_shaders[no_depth] = s
	return _shaders[no_depth]


## Image `e`'s quad made (once) and put where its values say.
func _place(e: Dictionary) -> void:
	if not e.has("_tex") or ed.view == null:
		return
	if _root == null or not is_instance_valid(_root):
		_root = Node3D.new()
		_root.name = "ReferenceImages"
		ed.view.sv.add_child(_root)
	if _quad == null:
		_quad = QuadMesh.new()
	var mi: MeshInstance3D = e.get("_mi")
	if mi == null:
		mi = MeshInstance3D.new()
		mi.mesh = _quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = ShaderMaterial.new()
		_root.add_child(mi)
		e["_mi"] = mi
	var view: String = e["view"]
	var front: bool = e["layer"] == "front"
	var m: ShaderMaterial = mi.material_override
	m.shader = _shader(front)
	m.render_priority = -1 if front else -100   # (over: before the edit overlays; behind: first of all)
	m.set_shader_parameter("tex", e["_tex"])
	m.set_shader_parameter("opacity", clampf(float(e["opacity"]), 0.0, 1.0))
	m.set_shader_parameter("far", not front and view != "free")
	m.set_shader_parameter("fade", view != "free")
	var b := Basis()
	match view:
		"side": b = Basis.from_euler(Vector3(0, PI / 2, 0))   # (as the side view looks: from +X)
		"top": b = Basis.from_euler(Vector3(-PI / 2, 0, 0))
		"free": b = Basis.from_euler(Vector3(deg_to_rad(float(e["tilt"])), deg_to_rad(float(e["turn"])), 0))
	var at := Vector3(float(e["x"]), float(e["y"]), float(e["z"])) if view == "free" else b * Vector3(float(e["x"]), float(e["y"]), 0.0)
	var h := maxf(0.001, float(e["height"]))
	mi.transform = Transform3D(b * Basis.from_scale(Vector3(h * float(e.get("_aspect", 1.0)), h, 1.0)), at)
	mi.visible = bool(e["shown"])
	_request()


func _drop(e: Dictionary) -> void:
	var mi: MeshInstance3D = e.get("_mi")
	if mi and is_instance_valid(mi):
		mi.queue_free()
	e.erase("_mi")
	e.erase("_tex")


func _request() -> void:
	if ed and ed.view:
		ed.view.request()


# --- kept per model ---------------------------------------------------------------------

static func _read_all() -> Dictionary:
	if not FileAccess.file_exists(FILE):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	return d if d is Dictionary else {}


func _save_soon() -> void:
	if _save_due:
		return
	_save_due = true
	if is_inside_tree():
		get_tree().create_timer(0.4).timeout.connect(func(): if _save_due: _save_now())
	else:
		_save_now()


func _save_now() -> void:
	_save_due = false
	var all := _read_all()
	var out := []
	for e in images:
		var d := {}
		for k in e:
			if not str(k).begins_with("_"):
				d[k] = e[k]
		out.append(d)
	if out.is_empty():
		all.erase(_key)
	else:
		all[_key] = out
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all, "\t"))


# --- the panel ----------------------------------------------------------------------------

func build_right(box: VBoxContainer) -> void:
	box.add_child(EditorIcons.tipped(UI.section("REFERENCE IMAGES"), EditorIcons.tip("Reference images", "", "Pictures shown behind the model in the front, side and top views, to model over.")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.add_child(ed._btn("Add reference image", "m_ref_image", "", "A picture from anywhere on this computer (png, jpg, webp) shown in the view to model from -\nlined up with the front view at first, behind the model. Kept with this model.", open_dialog))
	_remove = ed._btn("Remove reference image", "delete", "", "Takes the picked reference image away (the picture file isn't touched).", func(): remove(_sel))
	row.add_child(_remove)
	_eye = ed._btn("Show / hide reference image", "eye", "", "Shows or hides the picked reference image (kept either way).", func():
		if _sel >= 0:
			set_value(_sel, "shown", not bool(images[_sel]["shown"])))
	row.add_child(_eye)
	box.add_child(row)
	_list = ItemList.new()
	_list.custom_minimum_size.y = 56
	_list.auto_height = true
	_list.add_theme_font_size_override("font_size", 13)
	_list.tooltip_text = EditorIcons.tip("Reference images", "", "This model's reference images: pick one to change it below.")
	_list.item_selected.connect(func(i): _sel = i; _fill_fields())
	box.add_child(_list)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	_detail = grid
	box.add_child(grid)
	var vo := OptionButton.new()
	for n in VIEW_NAMES:
		vo.add_item(n)
	vo.focus_mode = Control.FOCUS_NONE
	vo.add_theme_font_size_override("font_size", 14)
	vo.tooltip_text = EditorIcons.tip("Lined up with", "", "The view the picture is upright in (front, side, top - it shows while you look along that\nview, centred on the origin), or a free plane placed and turned anywhere in the scene.")
	vo.item_selected.connect(func(i): set_value(_sel, "view", VIEWS[i]); _fill_fields())
	_row(grid, "View", vo, "view")
	var lo := OptionButton.new()
	lo.add_item("Behind the model")
	lo.add_item("Over the model")
	lo.focus_mode = Control.FOCUS_NONE
	lo.add_theme_font_size_override("font_size", 14)
	lo.tooltip_text = EditorIcons.tip("Layer", "", "Behind: the model drawn over the picture. Over: the picture drawn over the model,\nsee-through by its opacity (the points and wireframe still on top).")
	lo.item_selected.connect(func(i): set_value(_sel, "layer", "front" if i == 1 else "back"))
	_row(grid, "Layer", lo, "layer")
	var op := HSlider.new()
	op.min_value = 0.0
	op.max_value = 1.0
	op.step = 0.01
	op.custom_minimum_size.x = 100
	op.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	op.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	op.tooltip_text = EditorIcons.tip("Opacity", "", "How solid the picture is: 0 - not seen, 1 - solid.")
	op.value_changed.connect(func(v): set_value(_sel, "opacity", v))
	_row(grid, "Opacity", op, "opacity")
	for f in [["height", "Size", 0.01, 1000.0, 0.01, "The picture's height in metres (its width follows its shape)."],
			["x", "Offset X", -1000.0, 1000.0, 0.01, "Moves the picture across (metres): a view's along its own right; a free plane's along X."],
			["y", "Offset Y", -1000.0, 1000.0, 0.01, "Moves the picture up or down (metres): a view's along its own up; a free plane's along Y."],
			["z", "Offset Z", -1000.0, 1000.0, 0.01, "A free plane's place along Z (metres)."],
			["turn", "Turn", -360.0, 360.0, 1.0, "A free plane turned round the up axis (degrees)."],
			["tilt", "Tilt", -360.0, 360.0, 1.0, "A free plane tipped forward or back (degrees)."]]:
		var s := SpinBox.new()
		s.min_value = f[2]
		s.max_value = f[3]
		s.step = f[4]
		s.allow_greater = true
		s.allow_lesser = f[0] != "height"
		s.custom_minimum_size.x = 80
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.tooltip_text = EditorIcons.tip(f[1], "", f[5])
		var key: String = f[0]
		s.value_changed.connect(func(v): set_value(_sel, key, v))
		_row(grid, f[1], s, key)
	_fill_list()


func _row(grid: GridContainer, text: String, c: Control, key: String) -> void:
	var l := UI.label(text, 13, UI.TEXT_DIM)
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.tooltip_text = c.tooltip_text
	grid.add_child(l)
	grid.add_child(c)
	_fields[key] = [l, c]


func open_dialog() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	fd.title = "Add a reference image"
	fd.use_native_dialog = true
	ed.add_child(fd)
	fd.file_selected.connect(func(f: String):
		fd.queue_free()
		add_file(f)
		ed._say("Reference image %s added - lined up with the front view (the panel changes it)." % f.get_file()))
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered_ratio(0.6)


func _fill_list() -> void:
	if _list == null:
		return
	_list.clear()
	for e in images:
		var i := _list.add_item("%s%s · %s" % ["" if e["shown"] else "(hidden) ", str(e["file"]).get_file(), VIEW_NAMES[maxi(0, VIEWS.find(e["view"]))]])
		_list.set_item_tooltip(i, "%s\n%s, %s" % [e["file"], VIEW_NAMES[maxi(0, VIEWS.find(e["view"]))], "over the model" if e["layer"] == "front" else "behind the model"])
	if _sel >= 0 and _sel < images.size():
		_list.select(_sel)
	_fill_fields()


func _fill_fields() -> void:
	if _detail == null:
		return
	var has := _sel >= 0 and _sel < images.size()
	_detail.visible = has
	_remove.disabled = not has
	_eye.disabled = not has
	if not has:
		return
	var e: Dictionary = images[_sel]
	(_fields["view"][1] as OptionButton).select(maxi(0, VIEWS.find(e["view"])))
	(_fields["layer"][1] as OptionButton).select(1 if e["layer"] == "front" else 0)
	(_fields["opacity"][1] as HSlider).set_value_no_signal(float(e["opacity"]))
	for k in ["height", "x", "y", "z", "turn", "tilt"]:
		(_fields[k][1] as SpinBox).set_value_no_signal(float(e[k]))
		var free_only: bool = k in ["z", "turn", "tilt"]
		for c in _fields[k]:
			(c as Control).visible = not free_only or e["view"] == "free"
