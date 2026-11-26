extends Window
## The Inspector (developer menu, Alt + right-click > Inspector): a window
## inside the game's (along its right edge; movable, resizable), showing
## live objects' values as they change. Top: the node tree (filterable;
## select a node to inspect it).
## Bottom: the inspected object's properties - its script's variables first,
## then the built-in ones - refreshed several times a second. Arrays,
## dictionaries and objects open into their contents; double-click an object
## to inspect it (Back returns). Numbers, text, booleans, vectors and colours
## can be edited in place (Enter sets the value on the live object). A field
## that isn't at its default (the script variable's declared value, or the
## engine's default for a built-in property) has a reset button (↺); Reset
## all puts every such field of the object back.

const REFRESH := 0.2
const W := 560
const BUILTIN := ["position", "global_position", "rotation", "scale", "visible", "modulate",
	"z_index", "process_mode", "size"]

var target: Object
var _history: Array = []           # WeakRefs of earlier targets (Back)
var _nodes: Tree
var _props: Tree
var _filter: LineEdit
var _path: Label
var _builtin: CheckBox
var _t := 0.0
var _editing := false
var _defaults := {}                # property -> [has a default, default] (the target's)
var _reset_all: Button
const SNAP := 24                   # px: an edge this near the game window's snaps to it
var docked := {}                   # SIDE_* -> true: edges flush with the game window's
var _last := Rect2i()
var _last_view := Vector2i()
const RESET := 7


func _init() -> void:
	title = "Inspector"
	visible = false
	force_native = false   # (inside the game's window - an embedded subwindow)
	transient = false
	exclusive = false
	wrap_controls = false
	min_size = Vector2i(380, 300)
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_requested.connect(hide)


func _ready() -> void:
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.11)
	bg.add_theme_stylebox_override("panel", sb)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 4)
	for side in ["left", "right", "top", "bottom"]:
		box.set("offset_" + side, 6 if side in ["left", "top"] else -6)
	add_child(box)

	var bar := HBoxContainer.new()
	box.add_child(bar)
	var back := Button.new()
	back.text = "◀ Back"
	back.pressed.connect(go_back)
	bar.add_child(back)
	var refresh := Button.new()
	refresh.text = "⟳ Tree"
	refresh.tooltip_text = "Rebuild the node tree"
	refresh.pressed.connect(rebuild_tree)
	bar.add_child(refresh)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter nodes..."
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.text_changed.connect(func(_t): rebuild_tree())
	bar.add_child(_filter)

	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	_nodes = Tree.new()
	_nodes.custom_minimum_size.y = 160
	_nodes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_nodes.size_flags_stretch_ratio = 0.6
	_nodes.item_selected.connect(_on_node_selected)
	_nodes.item_collapsed.connect(_on_node_collapsed)
	split.add_child(_nodes)

	var lower := VBoxContainer.new()
	lower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(lower)
	var head := HBoxContainer.new()
	lower.add_child(head)
	_path = Label.new()
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.clip_text = true
	_path.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	head.add_child(_path)
	_builtin = CheckBox.new()
	_builtin.text = "Built-in"
	_builtin.tooltip_text = "Also show the engine's properties (position, scale, ...)"
	_builtin.toggled.connect(func(_on): _rebuild_props())
	head.add_child(_builtin)
	_props = Tree.new()
	_props.columns = 2
	_props.hide_root = true
	_props.column_titles_visible = true
	_props.set_column_title(0, "Property")
	_props.set_column_title(1, "Value")
	_props.set_column_expand_ratio(0, 2)
	_props.set_column_expand_ratio(1, 3)
	_props.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_props.item_activated.connect(_on_prop_activated)
	_props.item_edited.connect(_on_prop_edited)
	_props.item_collapsed.connect(_on_prop_collapsed)
	lower.add_child(_props)
	rebuild_tree()


## Show it right of the game's window (inside the screen if there's no room).
## Show it inside the game's window, along its right edge (the first time -
## after that where it was left: drag the title bar to move it, an edge to
## resize it).
func open() -> void:
	var view := get_tree().root.get_visible_rect().size
	if not has_meta("placed"):
		# Docked to the right edge, top to bottom.
		var m := frame_margins()
		var w := mini(W, int(view.x * 0.45))
		size = Vector2i(w, maxi(300, int(view.y - m[1] - m[3])))
		position = Vector2i(int(view.x - m[2]) - w, int(m[1]))
		docked = {SIDE_RIGHT: true, SIDE_TOP: true, SIDE_BOTTOM: true}
		_last = Rect2i(position, size)
		set_meta("placed", true)
	else:   # (keep it on screen if the game's window shrank)
		position = Vector2i(clampi(position.x, 0, maxi(0, int(view.x) - size.x)), clampi(position.y, 0, maxi(0, int(view.y) - 40)))
	show()
	grab_focus()
	rebuild_tree()
	if target == null:
		var link := get_parent()
		var m: Node = link.main() if link and link.has_method("main") else null
		inspect(m.get("ship") if m else get_tree().root)


func inspect(obj: Object, remember := true) -> void:
	if remember and is_instance_valid(target) and target != obj:
		_history.append(weakref(target))
	target = obj
	_rebuild_props()
	_select_in_tree(obj)


func go_back() -> void:
	while not _history.is_empty():
		var o: Object = _history.pop_back().get_ref()
		if is_instance_valid(o):
			inspect(o, false)
			return


# --- The node tree ------------------------------------------------------------------

func rebuild_tree() -> void:
	if _nodes == null:
		return
	_nodes.clear()
	var f := _filter.text.strip_edges().to_lower()
	var top := _nodes.create_item()
	_set_node_item(top, get_tree().root)
	if f == "":
		_add_kids(top, get_tree().root, 0)
	else:
		_add_matches(top, get_tree().root, f, 0)


## A node's label: Godot's made-up names (@Node2D@494) give way to its own.
static func node_label(n: Node) -> String:
	var s := str(n.name)
	if s.begins_with("@"):
		for k in ["display_name", "type_id"]:
			var v = n.get(k)
			if v is String and v != "":
				return "%s  (%s)" % [v, s]
	return s


func _set_node_item(it: TreeItem, n: Node) -> void:
	var s := node_label(n)
	if n.get_script() and n.get_script().resource_path != "":
		s += "  · " + n.get_script().resource_path.get_file().get_basename()
	else:
		s += "  · " + n.get_class()
	it.set_text(0, s)
	it.set_metadata(0, n.get_instance_id())
	if n == self:
		it.set_custom_color(0, Color(0.5, 0.5, 0.5))


## Two levels at a time; deeper ones fill when opened.
func _add_kids(it: TreeItem, n: Node, depth: int) -> void:
	for c in n.get_children():
		if c == self:
			continue
		var ci := _nodes.create_item(it)
		_set_node_item(ci, c)
		if c.get_child_count() > 0:
			if depth < 1:
				_add_kids(ci, c, depth + 1)
			else:
				_nodes.create_item(ci).set_text(0, "...")
			ci.collapsed = depth >= 1 or c.get_child_count() > 30


func _add_matches(it: TreeItem, n: Node, f: String, depth: int) -> void:
	if depth > 12:
		return
	for c in n.get_children():
		if c == self:
			continue
		var name_hit: bool = str(c.name).to_lower().contains(f) or (c.get_script() != null and c.get_script().resource_path.get_file().to_lower().contains(f))
		if name_hit:
			var ci := _nodes.create_item(it)
			_set_node_item(ci, c)
			ci.set_text(0, str(c.get_path()).trim_prefix("/root/") + ("  · " + c.get_script().resource_path.get_file().get_basename() if c.get_script() else ""))
		_add_matches(it, c, f, depth + 1)


func _on_node_collapsed(it: TreeItem) -> void:
	if it.collapsed:
		return
	var first := it.get_first_child()
	if first and first.get_text(0) == "..." and first.get_metadata(0) == null:
		first.free()
		var n := instance_from_id(it.get_metadata(0)) as Node
		if is_instance_valid(n):
			_add_kids(it, n, 1)
			for c in it.get_children():
				c.collapsed = true


func _on_node_selected() -> void:
	var it := _nodes.get_selected()
	if it == null or it.get_metadata(0) == null:
		return
	var n := instance_from_id(it.get_metadata(0))
	if is_instance_valid(n) and n != target:
		inspect(n)


func _select_in_tree(obj: Object) -> void:
	if _nodes == null or not (obj is Node) or not obj.is_inside_tree():
		_nodes.deselect_all() if _nodes else null
		return
	# Open the way down to it (deeper rows are only made when opened).
	var chain: Array = []
	var a: Node = obj
	while a:
		chain.push_front(a)
		a = a.get_parent()
	var cur := _nodes.get_root()
	for i in range(1, chain.size()):
		if cur == null:
			break
		if cur.collapsed:
			cur.collapsed = false   # (fills it - item_collapsed)
		var next: TreeItem = null
		for c in cur.get_children():
			if c.get_metadata(0) == chain[i].get_instance_id():
				next = c
				break
		cur = next
	var it := _find_item(_nodes.get_root(), obj.get_instance_id())
	if it and not it.is_selected(0):
		var p := it.get_parent()
		while p:
			p.collapsed = false
			p = p.get_parent()
		it.select(0)
		_nodes.scroll_to_item(it)


func _find_item(it: TreeItem, id: int) -> TreeItem:
	if it == null:
		return null
	if it.get_metadata(0) == id:
		return it
	for c in it.get_children():
		var r := _find_item(c, id)
		if r:
			return r
	return null


# --- The properties ------------------------------------------------------------------

func _names() -> Array:
	var out := []
	if not is_instance_valid(target):
		return out
	var built := []
	for p in target.get_property_list():
		var u: int = p["usage"]
		if u & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(p["name"])
		elif _builtin.button_pressed and (u & PROPERTY_USAGE_EDITOR) and p["name"] != "script":
			built.append(p["name"])
		elif p["name"] in BUILTIN:
			built.append(p["name"])
	if not _builtin.button_pressed:
		built = built.filter(func(n): return n in BUILTIN)
	return out + built


func _rebuild_props() -> void:
	if _props == null:
		return
	_props.clear()
	var root := _props.create_item()
	if not is_instance_valid(target):
		_path.text = "(nothing - or it was freed)"
		return
	_path.text = _describe(target)
	_path.tooltip_text = _path.text
	_defaults.clear()
	for n in _names():
		var it := _props.create_item(root)
		it.set_text(0, n)
		it.set_metadata(0, [n])   # (the path of keys from the target)
		_show(it, target.get(n))
	_t = REFRESH


func _describe(o: Object) -> String:
	if o is Node:
		var s := str(o.get_path()) if o.is_inside_tree() else str(o.name)
		return s + ("  (%s)" % o.get_script().resource_path.get_file() if o.get_script() else "  (%s)" % o.get_class())
	if o is Resource and o.resource_path != "":
		return "%s  (%s)" % [o.resource_path, o.get_class()]
	return "<%s #%d>" % [o.get_class(), o.get_instance_id()]


## The value in an item's column 1 (+ an openable placeholder for containers).
func _show(it: TreeItem, v: Variant) -> void:
	var text := _brief(v)
	if it.get_text(1) != text and not (_editing and it == _props.get_edited()):
		it.set_text(1, text)
	var t := typeof(v)
	var editable := t in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_COLOR, TYPE_BOOL]
	it.set_editable(1, editable and _is_settable(it))
	it.set_custom_color(1, Color(0.6, 0.85, 1.0) if t == TYPE_OBJECT else (Color(1, 0.8, 0.5) if t in [TYPE_INT, TYPE_FLOAT] else Color(0.88, 0.9, 0.95)))
	var opens: bool = (t == TYPE_OBJECT and is_instance_valid(v)) or ((v is Array or v is Dictionary or t >= TYPE_PACKED_BYTE_ARRAY) and v.size() > 0)
	if opens and it.get_child_count() == 0:
		_props.create_item(it).set_text(0, "...")
		it.collapsed = true
	elif not opens and it.get_child_count() > 0:
		for c in it.get_children():
			c.free()
	var keys = it.get_metadata(0)
	if keys is Array and keys.size() == 1:
		_show_reset(it, keys[0], v)


## While it has focus, Godot sends it every mouse click - even ones outside it,
## over the game (only a left click there takes the focus back): so an
## Alt + right-click reaching it opens the developer menu where it was made.
func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and mb.alt_pressed:
		var link := get_parent()
		if link and link.has_method("open_menu"):
			set_input_as_handled()
			link.open_menu(mb.position + Vector2(position))   # (its own coordinates -> the game view's)


# --- Snapping to the game window's edges ----------------------------------------

## The frame Godot draws round the window (title bar and border included) -
## [left, top, right, bottom] beyond its content.
func frame_margins() -> Array:
	var sb := get_theme_stylebox("embedded_border")
	if sb is StyleBoxFlat:
		return [sb.expand_margin_left, sb.expand_margin_top, sb.expand_margin_right, sb.expand_margin_bottom]
	return [0.0, float(get_theme_constant("title_height")), 0.0, 0.0]


## The window's frame, in the game view.
func frame_rect() -> Rect2:
	var m := frame_margins()
	return Rect2(Vector2(position) - Vector2(m[0], m[1]), Vector2(size) + Vector2(m[0] + m[2], m[1] + m[3]))


## Every frame: moved (by its title bar) - a frame edge near a game window
## edge snaps flush to it; resized (by an edge) - the moved edge snaps; the
## game window resized - docked edges follow it.
func snap() -> void:
	if not is_embedded():
		return
	var view := Vector2i(get_tree().root.get_visible_rect().size)
	var now := Rect2i(position, size)
	var view_changed := _last_view != Vector2i() and view != _last_view
	_last_view = view
	if now == _last and not view_changed:
		return
	var moved := now.position != _last.position and now.size == _last.size
	var resized := now.size != _last.size
	var m := frame_margins()
	var f := frame_rect()
	var pos := Vector2(position)
	var sz := Vector2(size)
	if view_changed and not moved and not resized:
		# (follow the game window: keep docked edges on its edges)
		if docked.has(SIDE_RIGHT):
			if docked.has(SIDE_LEFT):
				sz.x = view.x - m[0] - m[2]
			else:
				pos.x = view.x - m[2] - sz.x
		if docked.has(SIDE_BOTTOM):
			if docked.has(SIDE_TOP):
				sz.y = view.y - m[1] - m[3]
			else:
				pos.y = view.y - m[3] - sz.y
	elif moved:
		docked.clear()
		if absf(f.position.x) < SNAP:
			pos.x = m[0]
			docked[SIDE_LEFT] = true
		elif absf(f.end.x - view.x) < SNAP:
			pos.x = view.x - m[2] - sz.x
			docked[SIDE_RIGHT] = true
		if absf(f.position.y) < SNAP:
			pos.y = m[1]
			docked[SIDE_TOP] = true
		elif absf(f.end.y - view.y) < SNAP:
			pos.y = view.y - m[3] - sz.y
			docked[SIDE_BOTTOM] = true
	elif resized:
		# Only the edges that moved snap (the others stay where they are).
		if now.position.x != _last.position.x:   # left edge
			docked.erase(SIDE_LEFT)
			if absf(f.position.x) < SNAP:
				sz.x += pos.x - m[0]
				pos.x = m[0]
				docked[SIDE_LEFT] = true
		elif now.end.x != _last.end.x:            # right edge
			docked.erase(SIDE_RIGHT)
			if absf(f.end.x - view.x) < SNAP:
				sz.x = view.x - m[2] - pos.x
				docked[SIDE_RIGHT] = true
		if now.position.y != _last.position.y:   # top edge
			docked.erase(SIDE_TOP)
			if absf(f.position.y) < SNAP:
				sz.y += pos.y - m[1]
				pos.y = m[1]
				docked[SIDE_TOP] = true
		elif now.end.y != _last.end.y:            # bottom edge
			docked.erase(SIDE_BOTTOM)
			if absf(f.end.y - view.y) < SNAP:
				sz.y = view.y - m[3] - pos.y
				docked[SIDE_BOTTOM] = true
	sz = sz.max(Vector2(min_size))
	position = Vector2i(pos.round())
	size = Vector2i(sz.round())
	_last = Rect2i(position, size)


# --- Resetting to defaults ----------------------------------------------------------

## [has one, value]: a script variable's declared default (a constant
## expression - "var hull := -1.0"; not one computed at run time), or a
## built-in property's engine default. Objects aren't reset (no default
## node to point at).
func default_of(prop: String) -> Array:
	if typeof(_defaults) != TYPE_DICTIONARY:
		_defaults = {}
	if _defaults.has(prop):
		return _defaults[prop]
	var out := [false, null]
	if is_instance_valid(target):
		var cur: Variant = target.get(prop)
		var d: Variant = null
		var found := false
		var s: Script = target.get_script()
		var is_script_var := false
		for p in (s.get_script_property_list() if s else []):
			if p["name"] == prop:
				is_script_var = true
				break
		if is_script_var:
			var decl := declared_defaults(s)
			found = decl.has(prop)
			d = decl.get(prop)
		elif ClassDB.class_get_property_list(target.get_class()).any(func(p): return p["name"] == prop):
			d = ClassDB.class_get_property_default_value(target.get_class(), prop)
			found = true
		var numeric := [TYPE_INT, TYPE_FLOAT]
		var fits := typeof(d) == typeof(cur) or (typeof(d) in numeric and typeof(cur) in numeric)
		if found and fits and typeof(cur) != TYPE_OBJECT:
			out = [true, d]
	_defaults[prop] = out
	return out


static var _decl_cache := {}

## A script's variables' declared values (its own and its bases'): each
## top-level "var x := <value>" / "var x: T = <value>" (exported or not)
## whose value is a constant expression - literals, vectors, colours,
## arrays, dictionaries, maths, the script's constants. Read from the source
## and evaluated on the side: nothing of the game runs. Values worked out
## at run time ("var hull := max_hull", "@onready") have none.
static func declared_defaults(s: Script) -> Dictionary:
	var chain: Array = []
	var b := s
	while b:
		chain.push_front(b)
		b = b.get_base_script()
	var out := {}
	for sc in chain:
		out.merge(_own_defaults(sc), true)
	return out


static func _own_defaults(sc: Script) -> Dictionary:
	var src: String = sc.source_code
	if src == "" and sc.resource_path != "":
		src = FileAccess.get_file_as_string(sc.resource_path)
	var key := "%s:%d" % [sc.resource_path, src.hash()]
	if _decl_cache.has(key):
		return _decl_cache[key]
	var consts: Dictionary = sc.get_script_constant_map()
	var names := PackedStringArray()
	var values := []
	for k in consts:
		names.append(str(k))
		values.append(consts[k])
	var re := RegEx.create_from_string("^(?:@export\\w*(?:\\([^)]*\\))?\\s+)?var\\s+(\\w+)\\s*(?::\\s*[\\w\\[\\]\\.]+\\s*)?:?=\\s*(.+)$")
	var lines := src.split("\n")
	var out := {}
	var i := 0
	while i < lines.size():
		var m := re.search(lines[i])
		i += 1
		if m == null:
			continue
		var expr := _strip_comment(m.get_string(2))
		# (a value over several lines: read on until the brackets close)
		var extra := 0
		while _open_brackets(expr) > 0 and i < lines.size() and extra < 40:
			expr += " " + _strip_comment(lines[i].strip_edges())
			i += 1
			extra += 1
		var e := Expression.new()
		if e.parse(expr.strip_edges(), names) != OK:
			continue
		var v: Variant = e.execute(values, null, false)
		if not e.has_execute_failed() and typeof(v) != TYPE_OBJECT:
			out[m.get_string(1)] = v
	_decl_cache[key] = out
	return out


static func _strip_comment(s: String) -> String:
	var q := ""
	for i in s.length():
		var c := s[i]
		if q != "":
			if c == q and (i == 0 or s[i - 1] != "\\"):
				q = ""
		elif c == "\"" or c == "'":
			q = c
		elif c == "#":
			return s.substr(0, i).strip_edges()
	return s.strip_edges()


static func _open_brackets(s: String) -> int:
	var n := 0
	for c in s:
		if c in "([{":
			n += 1
		elif c in ")]}":
			n -= 1
	return n


static func same(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(a), float(b))
	if typeof(a) != typeof(b):
		return false
	return a == b


func is_default(prop: String) -> bool:
	var d := default_of(prop)
	return not d[0] or same(target.get(prop), d[1])


## Put a property back to its default (true: it had one).
func reset(prop: String) -> bool:
	var d := default_of(prop)
	if not d[0] or not is_instance_valid(target):
		return false
	var v: Variant = d[1]
	if v is Array or v is Dictionary:
		v = v.duplicate(true)   # (not the script's own copy)
	target.set(prop, v)
	_refresh_now()
	return true


func reset_all() -> int:
	var n := 0
	for prop in _names():
		if not is_default(prop) and reset(prop):
			n += 1
	return n


func _show_reset(it: TreeItem, prop: String, v: Variant) -> void:
	var d := default_of(prop)
	var differs: bool = d[0] and not same(v, d[1])
	var has := it.get_button_by_id(1, RESET) >= 0
	if differs and not has:
		it.add_button(1, EditorIcons.get_icon("undo"), RESET, false, "Reset to the default: " + _brief(d[1]))
	elif not differs and has:
		it.erase_button(1, it.get_button_by_id(1, RESET))


func _on_prop_button(it: TreeItem, _col: int, id: int, _mb: int) -> void:
	if id == RESET and it.get_metadata(0) is Array:
		reset(it.get_metadata(0)[0])


func _refresh_now() -> void:
	if _props and _props.get_root():
		_refresh(_props.get_root())


## The reset controls (made here, not in _ready, so a hot-reloaded open
## Inspector gets them too).
func _ensure_reset_ui() -> void:
	if not _props.button_clicked.is_connected(_on_prop_button):
		_props.button_clicked.connect(_on_prop_button)
	if _reset_all == null and _builtin:
		_reset_all = Button.new()
		_reset_all.text = "Reset all"
		_reset_all.icon = EditorIcons.get_icon("undo")
		_reset_all.tooltip_text = "Put every field that isn't at its default back to it"
		_reset_all.pressed.connect(reset_all)
		_builtin.get_parent().add_child(_reset_all)
		_builtin.get_parent().move_child(_reset_all, _builtin.get_index())


## Only properties of the target and entries inside its arrays / dictionaries
## (not things inside another object - inspect that one to change it).
func _is_settable(it: TreeItem) -> bool:
	var keys: Array = it.get_metadata(0)
	for i in range(keys.size() - 1):
		var parent: Variant = _value_at(keys.slice(0, i + 1))
		if typeof(parent) == TYPE_OBJECT:
			return false
	return true


func _brief(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_FLOAT:
			return str(snappedf(v, 0.001))
		TYPE_VECTOR2:
			return "(%s, %s)" % [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]
		TYPE_STRING:
			return '"%s"' % v
		TYPE_OBJECT:
			if not is_instance_valid(v):
				return "<freed>"
			if v is Node:
				return "%s  <%s>" % [v.name, v.get_script().resource_path.get_file() if v.get_script() else v.get_class()]
			if v is Resource and v.resource_path != "":
				return "<%s> %s" % [v.get_class(), v.resource_path.get_file()]
			return "<%s>" % v.get_class()
		TYPE_ARRAY:
			return "Array (%d)" % v.size()
		TYPE_DICTIONARY:
			return "Dictionary (%d)" % v.size()
	if typeof(v) >= TYPE_PACKED_BYTE_ARRAY:
		return "%s (%d)" % [type_string(typeof(v)), v.size()]
	return str(v)


## The value at a key path from the target ([prop, index/key, ...]).
func _value_at(keys: Array) -> Variant:
	if not is_instance_valid(target):
		return null
	var v: Variant = target.get(keys[0])
	for i in range(1, keys.size()):
		var k = keys[i]
		if typeof(v) == TYPE_OBJECT:
			if not is_instance_valid(v):
				return null
			v = v.get(k)
		elif v is Dictionary:
			v = v.get(k)
		elif (v is Array or typeof(v) >= TYPE_PACKED_BYTE_ARRAY) and typeof(k) == TYPE_INT and k < v.size():
			v = v[k]
		else:
			return null
	return v


## Opening a row fills it - after the Tree's own click handling (changing
## the tree inside its signal can leave it half-built).
func _on_prop_collapsed(it: TreeItem) -> void:
	if not it.collapsed:
		_fill_children.call_deferred(it)


func _fill_children(it: TreeItem) -> void:
	if not is_instance_valid(it) or it.get_tree() != _props:
		return
	for c in it.get_children():
		c.free()
	var keys: Array = it.get_metadata(0)
	var v: Variant = _value_at(keys)
	var sub := []   # [label, key]
	if typeof(v) == TYPE_OBJECT and is_instance_valid(v):
		for p in v.get_property_list():
			if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE or p["name"] in BUILTIN:
				sub.append([p["name"], p["name"]])
	elif v is Dictionary:
		for k in v.keys():
			sub.append([str(k), k])
	elif v is Array or typeof(v) >= TYPE_PACKED_BYTE_ARRAY:
		for i in mini(v.size(), 200):
			sub.append(["[%d]" % i, i])
	for s in sub.slice(0, 300):
		var ci := _props.create_item(it)
		if ci == null:
			return
		ci.set_text(0, s[0])
		ci.set_metadata(0, keys + [s[1]])
		_show(ci, _value_at(keys + [s[1]]))


func _process(delta: float) -> void:
	if not visible:
		return
	snap()
	_ensure_reset_ui()
	_t -= delta
	if _t > 0.0:
		return
	_t = REFRESH
	if target != null and not is_instance_valid(target):
		_path.text = "(freed)"
		return
	if _props.get_root() == null:
		return
	_refresh(_props.get_root())


func _refresh(it: TreeItem) -> void:
	for c in it.get_children():
		var keys = c.get_metadata(0)
		if keys == null:
			continue
		var v: Variant = _value_at(keys)
		_show(c, v)
		if not c.collapsed:
			_refresh(c)


## Double-click: an object opens in the inspector.
func _on_prop_activated() -> void:
	var it := _props.get_selected()
	if it == null or it.get_metadata(0) == null:
		return
	var v: Variant = _value_at(it.get_metadata(0))
	if typeof(v) == TYPE_OBJECT and is_instance_valid(v):
		inspect(v)
	elif it.is_editable(1):
		_editing = true
		_props.edit_selected(true)


func _on_prop_edited() -> void:
	_editing = false
	var it := _props.get_edited()
	if it == null:
		return
	var keys: Array = it.get_metadata(0)
	var old: Variant = _value_at(keys)
	var nv: Variant = parse_value(it.get_text(1), old)
	if nv == null:
		it.set_text(1, _brief(old))
		return
	set_at(keys, nv)
	_show(it, _value_at(keys))


## Text typed in the value column -> a value of the old one's type (null: invalid).
static func parse_value(s: String, old: Variant) -> Variant:
	s = s.strip_edges()
	match typeof(old):
		TYPE_INT:
			return int(s) if s.is_valid_int() or s.is_valid_float() else null
		TYPE_FLOAT:
			return float(s) if s.is_valid_float() or s.is_valid_int() else null
		TYPE_BOOL:
			return s.to_lower() in ["true", "1", "yes", "on"]
		TYPE_STRING:
			return s.trim_prefix('"').trim_suffix('"')
		TYPE_STRING_NAME:
			return StringName(s.trim_prefix('"').trim_suffix('"'))
		TYPE_COLOR:
			return Color.from_string(s, old) if not s.begins_with("(") else str_to_var("Color" + s)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			var parts := s.trim_prefix("(").trim_suffix(")").split(",")
			if parts.size() != 2 or not parts[0].strip_edges().is_valid_float() or not parts[1].strip_edges().is_valid_float():
				return null
			var v2 := Vector2(float(parts[0]), float(parts[1]))
			return v2 if typeof(old) == TYPE_VECTOR2 else Vector2i(v2)
	return null


## Set the value at a key path (containers are values: write them back up).
func set_at(keys: Array, v: Variant) -> void:
	if keys.size() == 1:
		target.set(keys[0], v)
		return
	var parent: Variant = _value_at(keys.slice(0, keys.size() - 1))
	var k = keys[-1]
	if parent is Dictionary or parent is Array:
		parent[k] = v   # (arrays and dictionaries are shared - this is live)
	elif typeof(parent) >= TYPE_PACKED_BYTE_ARRAY:
		parent[k] = v
		set_at(keys.slice(0, keys.size() - 1), parent)   # (packed arrays are copies)
