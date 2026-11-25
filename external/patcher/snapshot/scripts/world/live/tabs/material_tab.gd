extends VBoxContainer
## The Live Editor's Materials tab: the looks of what's picked - each surface's
## material: a shader's every parameter (numbers - sliders where the shader gives a
## range -, colours, vectors, ticks, textures), a standard material's colour, metal,
## roughness, glow and textures; and the thing's own per-instance values. Textures
## are replaced with a picture of yours. Edits change the material itself, so
## everything sharing it changes ("Its own copy" first to change only this kind).
## Kept (LiveEdits, section "material"): {rel path: {"<surface>": {"own": bool,
## param: value | {"tex": res path}}, "inst": {param: value}}}.

const TITLE := "Materials"
const ICON := "paint"
const DIR := "res://art/live/tex/"
## A standard material's parameters shown.
## [property, slider range, what it is (the row's tooltip)]
const STANDARD := [["albedo_color", "", "The surface's base colour (tinting its colour texture, if any)."],
	["metallic", "0,1,0.01", "How metal it is: 0 paint, plastic, stone; 1 bare metal (reflects its surroundings in its own colour)."],
	["roughness", "0,1,0.01", "How rough the surface is: 0 a mirror-sharp shine, 1 matt."],
	["emission_enabled", "", "Glow: the surface gives off light of its own (Emission)."],
	["emission", "", "The glow's colour (with Emission enabled)."],
	["emission_energy_multiplier", "0,16,0.01", "How bright the glow is (with Emission enabled)."],
	["albedo_texture", "", ""], ["normal_texture", "", ""], ["roughness_texture", "", ""], ["metallic_texture", "", ""],
	["emission_texture", "", ""],
	["uv1_scale", "", "How many times the textures repeat across the surface (x, y, z)."]]
## A texture slot's tooltip.
const TEXTURES := {"albedo_texture": "The colour picture on the surface.", "normal_texture": "The bumps' picture (a normal map): fine relief without geometry.",
	"roughness_texture": "Roughness over the surface (a greyscale picture: white matt).", "metallic_texture": "Metal over the surface (a greyscale picture: white metal).",
	"emission_texture": "Where and how it glows (a picture: black no glow)."}

static var pending := {}        # res path -> Image (pictures chosen this session, written with the edits)
static var _tex := {}           # res path -> Texture2D
static var _hooked := false

var ed: Node
var _gi: GeometryInstance3D
var _rel := "."
var _dialog: FileDialog


static func handles(n: Node) -> bool:
	return _first_geometry(n) != null


static func _first_geometry(n: Node) -> GeometryInstance3D:
	if n is GeometryInstance3D:
		return n
	var all := n.find_children("*", "GeometryInstance3D", true, false)
	return all[0] if not all.is_empty() else null


func bind(e: Node) -> void:
	ed = e
	if not _hooked:
		_hooked = true
		LiveEdits.before_save.append(flush)
	_gi = _first_geometry(ed.selected)
	_rel = LiveEdits.rel_path(ed.anchor, _gi) if ed.anchor else "."
	if _gi != ed.selected:
		add_child(UI.label("Its part: " + LiveEditor._name_of(_gi), 14, UI.TEXT_DIM))
	var n := surfaces(_gi)
	for s in n:
		var mat := material_of(_gi, s)
		add_child(LiveFields.head("SURFACE %d  ·  %s" % [s, _mat_name(mat)]))
		if mat == null:
			continue
		var own := UI.button("Its own copy", func(): _make_own(s), 13)
		own.tooltip_text = "Gives this kind of thing its own copy of the material, so edits change only it (not everything sharing it)."
		add_child(own)
		_params(mat, s)
	var inst := _instance_params(_gi)
	if not inst.is_empty():
		add_child(LiveFields.head("THIS THING'S OWN VALUES"))
		for p in inst:
			var name: String = p.trim_prefix("instance_shader_parameters/")
			add_child(LiveFields.row(name.capitalize(), _gi.get(p), func(v):
				_gi.set(p, v)
				_keep("inst", name, LiveEdits.enc(v)), "", "This thing's own value of its shader's \"%s\" (instance uniform): only this one changes." % name))


func unbind() -> void:
	ed = null


static func surfaces(gi: GeometryInstance3D) -> int:
	if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
		return (gi as MeshInstance3D).mesh.get_surface_count()
	return 1


## The material drawing surface `s` of `gi` (its override, the surface's, or the mesh's).
static func material_of(gi: GeometryInstance3D, s: int) -> Material:
	if gi.material_override:
		return gi.material_override
	if gi is MeshInstance3D:
		var mi := gi as MeshInstance3D
		if mi.get_surface_override_material(s):
			return mi.get_surface_override_material(s)
		if mi.mesh and s < mi.mesh.get_surface_count():
			return mi.mesh.surface_get_material(s)
	return null


static func _mat_name(m: Material) -> String:
	if m == null:
		return "(none)"
	if m is ShaderMaterial and (m as ShaderMaterial).shader:
		return (m as ShaderMaterial).shader.resource_path.get_file() if (m as ShaderMaterial).shader.resource_path != "" else "a shader"
	return m.get_class()


func _params(mat: Material, s: int) -> void:
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		if sm.shader == null:
			return
		for u in sm.shader.get_shader_uniform_list():
			var name: String = u["name"]
			var v = sm.get_shader_parameter(name)
			var t := int(u["type"])
			if v == null:
				v = _zero(t, str(u.get("hint_string", "")))
			if t == TYPE_OBJECT or v is Texture2D:
				add_child(_texture_row(name, v, s, func(tex): sm.set_shader_parameter(name, tex)))
				continue
			if t == TYPE_VECTOR4 and str(u.get("hint_string", "")).contains("source_color") or (t == TYPE_COLOR):
				v = Color(v.x, v.y, v.z, v.w) if v is Vector4 else v
			var hint := str(u["hint_string"]) if int(u["hint"]) == PROPERTY_HINT_RANGE else ""
			add_child(LiveFields.row(name.capitalize(), v, func(nv):
				sm.set_shader_parameter(name, nv)
				_keep(str(s), name, LiveEdits.enc(nv)), hint, _uniform_about(sm.shader, name, t)))
	elif mat is BaseMaterial3D:
		for p in STANDARD:
			var v = mat.get(p[0])
			if p[0].ends_with("_texture"):
				add_child(_texture_row(p[0], v, s, func(tex): mat.set(p[0], tex)))
				continue
			add_child(LiveFields.row(str(p[0]).capitalize(), v, func(nv):
				mat.set(p[0], nv)
				_keep(str(s), p[0], LiveEdits.enc(nv)), p[1], str(p[2]) + "\nChanges everything sharing this material."))


## A shader parameter's tooltip text: which uniform of which shader, its type.
static func _uniform_about(sh: Shader, name: String, t: int) -> String:
	var file := sh.resource_path.get_file() if sh and sh.resource_path != "" else "the shader"
	return "The shader parameter \"%s\" (%s) of %s.\nChanges everything sharing this material." % [name, type_string(t), file]


static func _zero(t: int, _hint: String) -> Variant:
	match t:
		TYPE_FLOAT: return 0.0
		TYPE_INT: return 0
		TYPE_BOOL: return false
		TYPE_VECTOR2: return Vector2.ZERO
		TYPE_VECTOR3: return Vector3.ZERO
		TYPE_VECTOR4: return Vector4.ZERO
		TYPE_COLOR: return Color.WHITE
	return null


func _texture_row(name: String, v: Variant, s: int, set_tex: Callable) -> Control:
	var h := HBoxContainer.new()
	var l := UI.label(name.capitalize(), 13, UI.TEXT_DIM)
	l.custom_minimum_size.x = 130
	l.clip_text = true
	l.tooltip_text = EditorIcons.tip(name.capitalize(), "", str(TEXTURES.get(name, "A texture (picture) of the shader parameter \"%s\"." % name)))
	h.add_child(l)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(48, 48)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = v if v is Texture2D else null
	h.add_child(tr)
	var info := UI.label(("%dx%d" % [(v as Texture2D).get_width(), (v as Texture2D).get_height()]) if v is Texture2D else "(none)", 13, UI.TEXT_DIM)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	if not OS.has_feature("web") and not v is Texture3D:
		var b := UI.button("Replace", func():
			_pick_picture(func(path: String):
				var img := Image.load_from_file(path)
				if img == null:
					ed.say("Couldn't read " + path.get_file())
					return
				img.generate_mipmaps()
				var tex := ImageTexture.create_from_image(img)
				var res_path := DIR + path.get_file().get_basename().validate_filename() + ".png"
				pending[res_path] = img
				_tex[res_path] = tex
				set_tex.call(tex)
				tr.texture = tex
				info.text = "%dx%d" % [img.get_width(), img.get_height()]
				_keep(str(s), name, {"tex": res_path})), 13)
		b.tooltip_text = "Replaces the texture with a picture of yours (PNG, JPG, WebP)."
		h.add_child(b)
	return h


func _pick_picture(cb: Callable) -> void:
	if _dialog:
		_dialog.queue_free()
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"])
	_dialog.use_native_dialog = true
	add_child(_dialog)
	_dialog.file_selected.connect(cb)
	_dialog.popup_centered(Vector2i(900, 600))


static func _instance_params(gi: GeometryInstance3D) -> Array:
	var out := []
	for p in gi.get_property_list():
		if str(p["name"]).begins_with("instance_shader_parameters/"):
			out.append(str(p["name"]))
	return out


## The surface's material made this kind's own (a copy on its part).
func _make_own(s: int) -> void:
	_own(_gi, s)
	_keep(str(s), "own", true)
	ed.say("This kind has its own copy of surface %d's material now." % s)
	var e = ed
	e.show_tab("material")


static func _own(gi: GeometryInstance3D, s: int) -> Material:
	var m := material_of(gi, s)
	if m == null or gi.has_meta("live_own_%d" % s):
		return m
	var c := m.duplicate()
	if gi.material_override:
		gi.material_override = c
	elif gi is MeshInstance3D:
		(gi as MeshInstance3D).set_surface_override_material(s, c)
	gi.set_meta("live_own_%d" % s, true)
	return c


func _keep(surface: String, param: String, v: Variant) -> void:
	if ed == null or ed.key == "":
		return
	var sec := LiveEdits.section(ed.key, "material")
	if not sec.has(_rel):
		sec[_rel] = {}
	if not sec[_rel].has(surface):
		sec[_rel][surface] = {}
	sec[_rel][surface][param] = v
	ed.edited("material")


## The pictures chosen this session written as PNGs (with the Live Editor's Save).
static func flush() -> void:
	var et: GDScript = load("res://scripts/editor/edit_target.gd")
	for path in pending:
		var to: String = et.write_path(path)
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		(pending[path] as Image).save_png(to)
	pending.clear()


static func texture_at(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	var et: GDScript = load("res://scripts/editor/edit_target.gd")
	var p: String = et.read_path(path)
	var t: Texture2D = null
	if ResourceLoader.exists(p) and not p.begins_with("user://"):
		t = load(p)   # (a mod's, through Mods' loader; the game's own, imported)
	if t == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path(p))
		if img:
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	_tex[path] = t
	return t


static func apply_edit(anchor: Node, data: Dictionary) -> void:
	for rel in data:
		var gi := LiveEdits.find(anchor, str(rel)) as GeometryInstance3D
		if gi == null:
			continue
		for surface in data[rel]:
			var vals: Dictionary = data[rel][surface]
			if surface == "inst":
				for p in vals:
					gi.set("instance_shader_parameters/" + str(p), LiveEdits.dec(vals[p]))
				continue
			var s := int(surface)
			var mat := _own(gi, s) if bool(vals.get("own", false)) else material_of(gi, s)
			if mat == null:
				continue
			for p in vals:
				if p == "own":
					continue
				var v = vals[p]
				if v is Dictionary and v.has("tex"):
					v = texture_at(str(v["tex"]))
				else:
					v = LiveEdits.dec(v)
				if mat is ShaderMaterial:
					(mat as ShaderMaterial).set_shader_parameter(str(p), v)
				else:
					mat.set(str(p), v)
