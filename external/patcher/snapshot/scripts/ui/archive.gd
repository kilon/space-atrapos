class_name Archive
extends HBoxContainer
## The Archive: all of the game's documentation in one place - a shelf of
## books, one browser for them all:
##   - Pilot's Guide (data/docs/game.md), Tutorial (data/docs/tutorial.md) and
##     the Talos Manual (data/docs/editor.md) - chapters and sections in the
##     docs' Markdown subset (EditorDocs);
##   - the Encyclopedia (Encyclopedia: what you've discovered, with its picture);
##   - Controls (every action and the keys bound to it now - Keybinds);
##   - Versions (each version of the game and its patches - data/patches).
## On the left: the title, a search across every book, the shelf and the open
## book's contents; on the right: where you are (book, chapter), the page, its
## picture and the pages before and after. Links ([..](doc:id)) go anywhere -
## another book's page too; Back / Forward (Alt + arrows, the mouse's side
## buttons) like a web browser. It's a tab of the Automaton and the Field
## Computer (embedded), and a window over anything else: F1, the Guide
## buttons, the tooltips' documentation links, the main menu (Archive.open).

## The shelf. `file`: a docs Markdown book (EditorDocs); the others are made here.
const BOOKS := [
	{"id": "guide", "title": "Pilot's Guide", "icon": "ui_guide", "file": "res://data/docs/game.md",
		"blurb": "How everything works: flying, fighting, stations, the computers, planets."},
	{"id": "tutorial", "title": "Tutorial", "icon": "help", "file": "res://data/docs/tutorial.md",
		"blurb": "First steps, lesson by lesson, in the order you'll need them."},
	{"id": "encyclopedia", "title": "Encyclopedia", "icon": "ui_codex",
		"blurb": "Ships, stations, gear, worlds and the lore of ancient Greece - what you've discovered."},
	{"id": "controls", "title": "Controls", "icon": "key",
		"blurb": "Every action and the keys and buttons bound to it now."},
	{"id": "versions", "title": "Versions", "icon": "patch",
		"blurb": "What each version of the game brought, patch by patch."},
	{"id": "talos", "title": "Talos Manual", "icon": "docs", "file": "res://data/docs/editor.md",
		"blurb": "The game's editor: data, sprites, meshes, animation - and mods."},
]

## The page contract of the computers' tabs (set before it's added).
var data: Node
var ship: Node2D
var surface: Node
## Shown as a window of its own (Archive.open) rather than a computer's tab.
var windowed := false
signal close_requested

var book := "guide"
var _current := ""            # "book/page"
var _back: Array = []
var _forward: Array = []
var _shelf := {}              # book id -> its button
var _toc: Tree
var _items := {}              # page -> TreeItem
var _search: LineEdit
var _crumb: RichTextLabel
var _title: Label
var _text: RichTextLabel
var _foot: RichTextLabel
var _pic_box: PanelContainer
var _pic: Encyclopedia.Preview
var _back_btn: Button
var _fwd_btn: Button
var _enc := {}                # encyclopedia page -> entry
var _enc_cats: Array = []
var _versions: Array = []     # [{id, title, date, summary, patches: [patch...]}]
var _built := false


func _ready() -> void:
	add_theme_constant_override("separation", 18)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	# Left: title, search, shelf, contents.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(360, 0)
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	var head := Label.new()
	head.text = "THE ARCHIVE"
	head.add_theme_font_override("font", NeonTheme.heavy_font())
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", NeonTheme.HEAD)
	left.add_child(head)
	left.add_child(UI.label("Every book of the game in one place.", 14, UI.TEXT_DIM))
	_search = LineEdit.new()
	_search.placeholder_text = "Search every book..."
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _fill_toc())
	_search.tooltip_text = "Finds pages in every book whose text has all these words."
	left.add_child(_search)
	var shelf := GridContainer.new()
	shelf.columns = 2
	shelf.add_theme_constant_override("h_separation", 6)
	shelf.add_theme_constant_override("v_separation", 6)
	for b in BOOKS:
		var btn := EditorIcons.dress(UI.button("", open_book.bind(b["id"]), 15), b["icon"], "%s\n%s" % [b["title"], b["blurb"]], b["title"])
		btn.toggle_mode = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 40)
		btn.focus_mode = FOCUS_NONE
		shelf.add_child(btn)
		_shelf[b["id"]] = btn
	left.add_child(shelf)
	_toc = Tree.new()
	_toc.hide_root = true
	_toc.size_flags_vertical = SIZE_EXPAND_FILL
	_toc.custom_minimum_size = Vector2(0, 360)
	_toc.focus_mode = FOCUS_NONE
	_toc.add_theme_font_size_override("font_size", 15)
	_toc.tooltip_text = "Contents\nThe chapters and pages of the book picked above: click one to read it."
	_toc.item_selected.connect(func():
		var it := _toc.get_selected()
		if it and str(it.get_metadata(0)) != "" and str(it.get_metadata(0)) != _current:
			show_page.call_deferred(str(it.get_metadata(0))))
	left.add_child(_toc)
	# Right: where you are, the page, the way on.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	_back_btn = EditorIcons.dress(Button.new(), "back", "Back      [Alt+Left]\nThe page you were reading before (like a web browser). The mouse's back button works too.")
	_back_btn.focus_mode = FOCUS_NONE
	_back_btn.pressed.connect(go_back)
	bar.add_child(_back_btn)
	_fwd_btn = EditorIcons.dress(Button.new(), "forward", "Forward      [Alt+Right]\nForward again to the page you came back from. The mouse's forward button works too.")
	_fwd_btn.focus_mode = FOCUS_NONE
	_fwd_btn.pressed.connect(go_forward)
	bar.add_child(_fwd_btn)
	_crumb = _rich(15)
	_crumb.fit_content = true
	_crumb.scroll_active = false
	_crumb.autowrap_mode = TextServer.AUTOWRAP_OFF
	_crumb.size_flags_horizontal = SIZE_EXPAND_FILL
	_crumb.size_flags_vertical = SIZE_SHRINK_CENTER
	bar.add_child(_crumb)
	if windowed:
		var x := EditorIcons.dress(UI.button("", func(): close_requested.emit(), 16), "close", "Close the Archive      [Esc]")
		x.focus_mode = FOCUS_NONE
		bar.add_child(x)
	right.add_child(bar)
	_title = Label.new()
	_title.add_theme_font_override("font", NeonTheme.heavy_font())
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", NeonTheme.INFO)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_title)
	var rule := ColorRect.new()
	rule.color = Color(NeonTheme.HEAD, 0.45)
	rule.custom_minimum_size = Vector2(0, 2)
	right.add_child(rule)
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	right.add_child(body)
	_text = _rich(17)
	_text.threaded = true   # (a long page laid out off the main thread: opening it no long frame)
	_text.progress_bar_delay = 400
	_text.size_flags_horizontal = SIZE_EXPAND_FILL
	_text.size_flags_vertical = SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(560, 420)
	body.add_child(_text)
	_pic_box = PanelContainer.new()
	_pic_box.add_theme_stylebox_override("panel", NeonTheme.box(Color(NeonTheme.HEAD, 0.6), NeonTheme.BG, 1, 4))
	_pic_box.size_flags_vertical = SIZE_SHRINK_BEGIN
	_pic = Encyclopedia.Preview.new()
	_pic.custom_minimum_size = Vector2(240, 240)
	_pic_box.add_child(_pic)
	_pic_box.hide()
	body.add_child(_pic_box)
	_foot = _rich(15)
	_foot.fit_content = true
	_foot.scroll_active = false
	right.add_child(_foot)
	_built = true
	if _current == "":
		open_book(book)
	else:
		var start := _current
		_current = ""
		_go(start)


func _rich(fs: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.add_theme_font_size_override("normal_font_size", fs)
	r.add_theme_font_size_override("bold_font_size", fs)
	r.add_theme_font_size_override("italics_font_size", fs)
	r.meta_clicked.connect(_on_link)
	return r


## (A computer's tab:) shown again, or the player's data changed - the
## encyclopedia follows your discoveries; the page stays.
func refresh() -> void:
	if not _built:
		return
	_enc_cats = []
	if book == "encyclopedia" or _search.text != "":
		_fill_toc()
	if _current.begins_with("encyclopedia/"):
		_show(_current)


# --- Opening a window -----------------------------------------------------------------

## Opens the Archive over everything (a layer of its own) at `page_id` ("book/page",
## or a page of `book_id`, or the book's first page). One window at a time.
static func open(owner: Node, book_id := "guide", page_id := "") -> Archive:
	var tree := owner.get_tree()
	if page_id != "" and not page_id.contains("/"):
		page_id = book_id + "/" + page_id
	for w in tree.get_nodes_in_group("archive_window"):
		var a: Archive = w.archive
		if page_id != "":
			a.show_page(page_id)
		else:
			a.open_book(book_id)
		return a
	var layer := CanvasLayer.new()
	layer.layer = 120
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(layer)
	var w := Window_.new()
	w.archive.book = book_id
	if page_id != "":
		w.archive.show_page(page_id)   # (before it's built: it opens there, no other page laid out first)
	layer.add_child(w)
	return w.archive


## The window form: the game dimmed behind, the Archive in a panel; Esc closes.
class Window_ extends Control:
	var archive: Archive

	func _init() -> void:
		add_to_group("archive_window")
		set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		theme = NeonTheme.build()
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.72)
		dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(dim)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", NeonTheme.box(Color(NeonTheme.HEAD, 0.8), Color(NeonTheme.BG, 0.985), 2, 10))
		panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		panel.offset_left = 150
		panel.offset_right = -150
		panel.offset_top = 70
		panel.offset_bottom = -70
		add_child(panel)
		var m := MarginContainer.new()
		for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			m.add_theme_constant_override(k, 16)
		panel.add_child(m)
		archive = Archive.new()
		archive.windowed = true
		archive.close_requested.connect(close)
		m.add_child(archive)

	func close() -> void:
		get_parent().queue_free()

	func _input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"):
			close()
			get_viewport().set_input_as_handled()
			return
		if archive._history_keys(event):
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if windowed or not is_visible_in_tree():
		return
	if _history_keys(event):
		get_viewport().set_input_as_handled()


func _history_keys(event: InputEvent) -> bool:
	var k := event as InputEventKey
	var mb := event as InputEventMouseButton
	var back: bool = (k != null and k.pressed and k.alt_pressed and k.keycode == KEY_LEFT) or (mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_XBUTTON1)
	var fwd: bool = (k != null and k.pressed and k.alt_pressed and k.keycode == KEY_RIGHT) or (mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_XBUTTON2)
	if back:
		go_back()
	elif fwd:
		go_forward()
	return back or fwd


# --- Navigation -----------------------------------------------------------------------------

func open_book(id: String) -> void:
	book = id
	if not _built:
		return
	var toc := contents(id)
	var first := ""
	for ch in toc:
		if ch["id"] != "":
			first = ch["id"]
			break
		if not ch["pages"].is_empty():
			first = ch["pages"][0][0]
			break
	if first != "":
		show_page(first)
	else:
		_fill_toc()


## Opens a page ("book/page"), remembering the current one for Back.
func show_page(pid: String) -> void:
	if not pid.contains("/"):
		pid = resolve(pid)
	if not _built:
		_current = pid
		book = pid.get_slice("/", 0)
		return
	if pid == _current:
		return
	if _current != "":
		_back.append(_current)
		_forward.clear()
	_go(pid)


func go_back() -> void:
	if _back.is_empty():
		return
	_forward.append(_current)
	_go(_back.pop_back())


func go_forward() -> void:
	if _forward.is_empty():
		return
	_back.append(_current)
	_go(_forward.pop_back())


func _go(pid: String) -> void:
	var b := pid.get_slice("/", 0)
	var changed := b != book
	book = b
	_current = pid
	for k in _shelf:
		_shelf[k].set_pressed_no_signal(k == book)
	if changed or not _items.has(pid):
		_fill_toc()
	var it: TreeItem = _items.get(pid)
	if it:
		var p := it.get_parent()
		while p:
			p.collapsed = false
			p = p.get_parent()
		it.select(0)
		_toc.scroll_to_item(it)
	_show(pid)
	_back_btn.disabled = _back.is_empty()
	_fwd_btn.disabled = _forward.is_empty()


## A link: "doc:id" - a page of the book it's in, else of whichever book has it.
func _on_link(meta: Variant) -> void:
	var m := str(meta)
	if m.begins_with("doc:"):
		show_page(resolve(m.substr(4)))


## "book/page" for a bare page id: the current book's if it has it, else the first book that does.
func resolve(id: String) -> String:
	if id.contains("/"):
		return id
	var order := [book] + BOOKS.map(func(b): return b["id"])
	for b in order:
		if has_page(b + "/" + id):
			return b + "/" + id
	return book + "/" + id


func has_page(pid: String) -> bool:
	var b := pid.get_slice("/", 0)
	var id := pid.substr(b.length() + 1)
	var f := _file(b)
	if f != "":
		EditorDocs.use(f)
		return EditorDocs.has(id)
	return not page(pid).is_empty()


# --- The books --------------------------------------------------------------------------------

func _book(id: String) -> Dictionary:
	for b in BOOKS:
		if b["id"] == id:
			return b
	return {}


func _file(id: String) -> String:
	return str(_book(id).get("file", ""))


## A book's contents: [{id (its own page, or ""), title, pages: [[page, title]...], hint}].
func contents(b: String) -> Array:
	var out := []
	var f := _file(b)
	if f != "":
		EditorDocs.use(f)
		for c in EditorDocs.chapters():
			var pages := []
			for s in c["sections"]:
				pages.append([b + "/" + s, EditorDocs.numbered(s)])
			out.append({"id": b + "/" + c["id"], "title": EditorDocs.numbered(c["id"]), "pages": pages})
		return out
	match b:
		"encyclopedia":
			for cat in _enc_categories():
				var pages := []
				for e in cat["entries"]:
					pages.append(["encyclopedia/" + str(e["id"]), e["title"]])
				out.append({"id": "", "title": cat["title"], "pages": pages, "hint": cat["hint"] if pages.is_empty() else ""})
		"controls":
			var pages := [["controls/overview", "Mouse and keys at a glance"]]
			for g in _key_groups():
				pages.append(["controls/" + g.to_lower(), g])
			out.append({"id": "", "title": "Controls", "pages": pages})
		"versions":
			for v in _versions_list():
				var pages := []
				for p in v["patches"]:
					pages.append(["versions/patch:" + str(p["id"]), "%s  %s" % [p["id"], p["title"]]])
				out.append({"id": "versions/" + str(v["id"]), "title": "Version %s  ·  %s" % [v["id"], v["title"]], "pages": pages})
	return out


## A page: {title, chapter (its chapter's page or ""), body (BBCode), entry (a picture's, or {}), text (searched)}.
## (`full` false: without the body - for the search.)
func page(pid: String, full := true) -> Dictionary:
	var b := pid.get_slice("/", 0)
	var id := pid.substr(b.length() + 1)
	var f := _file(b)
	if f != "":
		EditorDocs.use(f)
		if not EditorDocs.has(id):
			return {}
		var ch := EditorDocs.chapter_of(id)
		return {"title": ("Chapter " + EditorDocs.numbered(id)) if id.begins_with("ch:") else EditorDocs.numbered(id),
			"chapter": (b + "/" + ch) if ch != "" else "", "body": EditorDocs.body(id) if full else "", "entry": {}, "text": EditorDocs.text_of(id)}
	match b:
		"encyclopedia":
			_enc_categories()
			if not _enc.has(pid):
				return {}
			var e: Dictionary = _enc[pid]
			return {"title": e["title"], "chapter": "", "crumb": e.get("_cat", ""), "body": e["text"], "entry": e, "text": e["title"] + " " + e["text"]}
		"controls":
			if id == "overview":
				EditorDocs.use(_file("guide"))
				var t := EditorDocs.body("controls") if EditorDocs.has("controls") else ""
				return {"title": "Mouse and keys at a glance", "chapter": "", "body": t + "\n\n[color=#8fa3b8]Rebind any key or pad button in [b]Settings > Controls[/b] (the Esc menu). The other pages here list every action and what it's bound to now.[/color]", "entry": {}, "text": "controls mouse keys " + t}
			for g in _key_groups():
				if g.to_lower() == id:
					var lines := []
					var search: String = g
					for a in _kb().ACTIONS:
						if a[1] != g:
							continue
						var keys := _keys_of(a[0])
						lines.append("[cell][color=#e8d8c0]%s[/color][/cell][cell][b][color=#ffd27a]%s[/color][/b][/cell]" % [a[2], keys if keys != "" else "[color=#6a6a70]-[/color]"])
						search += " " + a[2] + " " + keys
					var body := "[table=2]" + "".join(lines) + "[/table]\n\n[color=#8fa3b8]As bound now. Rebind them in [b]Settings > Controls[/b].[/color]"
					return {"title": g, "chapter": "", "body": body, "entry": {}, "text": search}
		"versions":
			for v in _versions_list():
				if id == str(v["id"]):
					var lines := ["[color=#8fa3b8]%s[/color]\n" % v["date"], str(v["summary"]), "", "[b]Its patches[/b]"]
					for p in v["patches"]:
						lines.append("  •  [color=#7fd6ff][url=doc:versions/patch:%s]%s  %s[/url][/color]  [color=#8fa3b8](%s)[/color]" % [p["id"], p["id"], p["title"], p["date"]])
					lines.append("\n[color=#8fa3b8]The step-by-step infographics and the code review of every patch: [b]Patch Notes[/b] (the title screen).[/color]")
					return {"title": "Version %s  ·  %s" % [v["id"], v["title"]], "chapter": "", "body": "\n".join(lines), "entry": {}, "text": v["title"] + " " + str(v["summary"])}
				for p in v["patches"]:
					if id == "patch:" + str(p["id"]):
						var body2 := "[color=#8fa3b8]%s  ·  in version %s[/color]\n\n%s\n\n[color=#8fa3b8]Its infographic and code review: [b]Patch Notes[/b] (the title screen).[/color]" % [p["date"], v["id"], p["summary"]]
						return {"title": "Patch %s  ·  %s" % [p["id"], p["title"]], "chapter": "versions/" + str(v["id"]), "body": body2, "entry": {}, "text": p["title"] + " " + str(p["summary"])}
	return {}


func _enc_categories() -> Array:
	if _enc_cats.is_empty() and is_inside_tree():
		_enc_cats = Encyclopedia.categories(get_tree())
		_enc = {}
		for cat in _enc_cats:
			for e in cat["entries"]:
				e["_cat"] = cat["title"]
				_enc["encyclopedia/" + str(e["id"])] = e
	return _enc_cats


## The Keybinds autoload (by path: this class mustn't need it to compile).
func _kb() -> Node:
	return get_node("/root/Keybinds")


func _key_groups() -> Array:
	var out := []
	for a in _kb().ACTIONS:
		if not a[1] in out:
			out.append(a[1])
	return out


func _keys_of(id: String) -> String:
	var kb := get_node_or_null("/root/Keybinds")
	if kb == null:
		return ""
	var parts := []
	var binds: Array = kb.binds.get(id, ["", "", ""])
	for i in binds.size():
		var t: String = kb.spec_text(str(binds[i]))
		if t != "":
			parts.append(t if i < 2 else t + " (pad)")
	return "  ·  ".join(parts)


## The versions (newest first) with their patches, read from data/patches.
func _versions_list() -> Array:
	if not _versions.is_empty():
		return _versions
	var patches := {}
	var versions := []
	var dir := "res://data/patches/"
	for f in ResourceLoader.list_directory(dir):
		if not str(f).ends_with(".json"):
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + str(f)))
		if not d is Dictionary:
			continue
		if d.get("kind", "") == "version":
			versions.append(d)
		else:
			patches[str(d.get("id", ""))] = d
	versions.sort_custom(func(a, b): return str(a.get("date", "")) + str(a["id"]) > str(b.get("date", "")) + str(b["id"]))
	var used := {}
	for v in versions:
		var ps := []
		for pid in v.get("patches", []):
			if patches.has(str(pid)):
				ps.append(patches[str(pid)])
				used[str(pid)] = true
		_versions.append({"id": v["id"], "title": v.get("title", ""), "date": v.get("date", ""), "summary": v.get("summary", ""), "patches": ps})
	var loose := []
	for pid in patches:
		if not used.has(pid):
			loose.append(patches[pid])
	if not loose.is_empty():
		loose.sort_custom(func(a, b): return str(a["id"]) > str(b["id"]))
		_versions.push_front({"id": "next", "title": "Not yet in a version", "date": "", "summary": "Patches published since the last version.", "patches": loose})
	return _versions


# --- Showing ----------------------------------------------------------------------------------

## The contents tree: the open book's chapters and pages - or, searching,
## the pages of every book that have all the words.
func _fill_toc() -> void:
	_toc.clear()
	_items.clear()
	var root := _toc.create_item()
	var q := _search.text.strip_edges().to_lower()
	if q == "":
		for ch in contents(book):
			var ci := _toc.create_item(root)
			ci.set_text(0, ch["title"])
			ci.set_custom_color(0, NeonTheme.HEAD)
			ci.set_custom_font(0, NeonTheme.heavy_font())
			ci.set_metadata(0, ch["id"])
			ci.set_selectable(0, ch["id"] != "")
			if ch["id"] != "":
				_items[ch["id"]] = ci
			for p in ch["pages"]:
				var pi := _toc.create_item(ci)
				pi.set_text(0, p[1])
				pi.set_metadata(0, p[0])
				_items[p[0]] = pi
			if str(ch.get("hint", "")) != "":
				var hi := _toc.create_item(ci)
				hi.set_text(0, ch["hint"])
				hi.set_selectable(0, false)
				hi.set_custom_color(0, Color(0.5, 0.5, 0.55))
			ci.collapsed = book in ["versions", "encyclopedia"] and _current.get_slice("/", 0) == book and not ch["pages"].any(func(p): return p[0] == _current)
		return
	var words := Array(q.split(" ", false))
	var found := 0
	for b in BOOKS:
		var bi: TreeItem = null
		for ch in contents(b["id"]):
			var pages: Array = ([[ch["id"], ch["title"]]] if ch["id"] != "" else []) + ch["pages"]
			for p in pages:
				var pg := page(p[0], false)
				if pg.is_empty():
					continue
				var t := (str(pg["title"]) + " " + str(pg["text"])).to_lower()
				if words.all(func(w): return t.contains(w)):
					if bi == null:
						bi = _toc.create_item(root)
						bi.set_text(0, b["title"])
						bi.set_custom_color(0, NeonTheme.HEAD)
						bi.set_custom_font(0, NeonTheme.heavy_font())
						bi.set_selectable(0, false)
						bi.set_metadata(0, "")
					var it := _toc.create_item(bi)
					it.set_text(0, p[1])
					it.set_metadata(0, p[0])
					_items[p[0]] = it
					found += 1
	if found == 0:
		var none := _toc.create_item(root)
		none.set_text(0, "Nothing in any book has all of: " + q)
		none.set_selectable(0, false)
		none.set_custom_color(0, Color(0.6, 0.6, 0.62))


func _show(pid: String) -> void:
	var pg := page(pid)
	var b := _book(pid.get_slice("/", 0))
	if pg.is_empty():
		_title.text = "Not found"
		_text.text = "[color=#8fa3b8]This page isn't in the Archive (%s).[/color]" % pid
		_crumb.text = ""
		_foot.text = ""
		_pic_box.hide()
		return
	# Where you are: the book, the chapter (or the encyclopedia's category).
	var crumb := "[color=#ffb060]%s[/color]" % b.get("title", "")
	if str(pg.get("chapter", "")) != "":
		crumb += "  [color=#6a5a48]›[/color]  [color=#7fd6ff][url=doc:%s]%s[/url][/color]" % [pg["chapter"], page(pg["chapter"]).get("title", "")]
	elif str(pg.get("crumb", "")) != "":
		crumb += "  [color=#6a5a48]›[/color]  [color=#c8b8a0]%s[/color]" % pg["crumb"]
	_crumb.text = crumb
	_title.text = str(pg["title"])
	var e: Dictionary = pg["entry"]
	_pic_box.visible = not e.is_empty()
	if not e.is_empty():
		_pic.show_entry(e)
	var w := DocPictures.width_for(_text) if _text.size.x > 100 else 900.0
	_text.text = DocPictures.expand(str(pg["body"]), w, true)   # (pictures not loaded yet: in the background - _process)
	_text.scroll_to_line(0)
	_pictures_for = pid if not DocPictures.loaded(str(pg["body"])) else ""
	# The pages before and after (in the book's reading order).
	var order := []
	for ch in contents(pid.get_slice("/", 0)):
		if ch["id"] != "":
			order.append(ch["id"])
		for p in ch["pages"]:
			order.append(p[0])
	var i := order.find(pid)
	var nav := []
	if i > 0:
		nav.append("[url=doc:%s]◀  %s[/url]" % [order[i - 1], _short(order[i - 1])])
	if i >= 0 and i < order.size() - 1:
		nav.append("[url=doc:%s]%s  ▶[/url]" % [order[i + 1], _short(order[i + 1])])
	_foot.text = "[color=#3a4a5c]────────────────────────────────[/color]\n[color=#7fd6ff]%s[/color]" % "          ".join(nav) if not nav.is_empty() else ""


var _pictures_for := ""   # the page shown while its pictures load (shown again when they're in)
var _pic_t := 0.0

func _process(delta: float) -> void:
	if _pictures_for == "" or not is_visible_in_tree():
		return
	_pic_t -= delta
	if _pic_t > 0.0:
		return
	_pic_t = 0.1
	if _pictures_for != _current:
		_pictures_for = ""
		return
	var pg := page(_current)
	if DocPictures.loaded(str(pg.get("body", ""))):
		var line := _text.get_v_scroll_bar().value
		_text.text = DocPictures.expand(str(pg["body"]), DocPictures.width_for(_text) if _text.size.x > 100 else 900.0)
		_text.get_v_scroll_bar().value = line
		_pictures_for = ""


func _short(pid: String) -> String:
	return str(page(pid).get("title", pid)).trim_prefix("Chapter ")
