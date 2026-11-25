extends Control
## Versions - the Patcher (Talos > Versions, F7; the top of the rail): the game's patch notes, one entry per
## change - a short summary and a step-by-step infographic of what changed
## and how, drawn as vector graphics and animated step by step.
## Patches are data: data/patches/<id>.json
##   {id, title, date, summary, steps: [{title, text, diagram: [element...]}]}
## Versions group patches: data/patches/version_<id>_<name>.json
##   {kind: "version", id, title, date, summary, patches: [patch ids],
##    steps: [{title, text, diagram, patch: <patch id>}]}   - one page per patch
## The list is a tree: each version with its patches under it (newest first),
## patches in no version yet at the top level, unpublished changes first.
## Diagram elements live on a 1000 x 560 canvas (scaled to fit) - see
## PatchView for the kinds (box, text, arrow, circle, grid, iso, bar, badge,
## poly); each fades in after its "delay" (or one after another), "pulse"
## makes it glow.
## A patch can also carry a code review (the "Code review" tab):
##   review: {intro, files: [{path, explanation, added, removed,
##            hunks: [{title, note, diff (unified diff text), added, removed,
##                     bubbles: [{at, text}]}]}]}
## Bubbles explain how a part of the code works: each points (with an arrow)
## at the first diff line containing "at" (or line: its index in the diff),
## drawn over the code viewer in the empty space beside the code - see Bubbles.

const EDITOR_SCENE := "res://editor.tscn"
const DIR := "res://data/patches/"
const ACCENT := Color(0.95, 0.7, 0.3)

var patches: Array = []             # every entry, in the tree's order (a version, then its patches)
## True while the unpublished changes are being scanned (a worker thread).
var scanning := false
var _task := -1
var _parent: Array = []             # entry index -> its version's index (-1: top level)
var _items: Array = []              # entry index -> its TreeItem
var _selecting := false
var current := -1
var step := 0
var _list: Tree
var _title: Label
var _date: Label
var _summary: Label
var _view: PatchView
var _step_title: Label
var _step_text: Label
var _counter: Label
var _open_patch: Button             # (a version's page: opens that page's patch)
var _tabs: TabBar
var _info_box: VBoxContainer        # the infographic
var _review_box: VBoxContainer      # the code review
var _review_intro: Label
var _files: ItemList
var _review: RichTextLabel
var _bubbles: Bubbles               # (over the code viewer)
var _mono: SystemFont
var _asset_bar: HBoxContainer
var _asset_info: Label
var _player: AudioStreamPlayer
var _rows: Array = []               # file list row -> index into the review's files (-1: all assets)
var _tex_cache := {}
const IMAGES := ["png", "jpg", "jpeg", "webp", "svg"]
const SOUNDS := ["wav", "ogg", "mp3"]
const FONTS := ["ttf", "otf"]
const CODE := ["gd", "py", "gdshader", "glsl", "cs", "sh", "cpp", "h", "c"]   # (listed first in a review)


func _ready() -> void:
	load_patches()
	_build()
	if not patches.is_empty():
		show_patch(newest())


## Where Versions opens: the newest version (or patch) - its infographic,
## never the unpublished changes' code review.
func newest() -> int:
	for i in patches.size():
		if not patches[i].get("pending", false):
			return i
	return 0


## Reads every patch file (newest first).
func load_patches() -> void:
	patches = []
	_parent = []
	var found: Array = []
	var versions: Array = []
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			if not f.ends_with(".json"):
				continue
			var p = _read(DIR + f)
			if p is Dictionary and p.has("steps"):
				p["file"] = f
				if p.get("kind", "") == "version":
					versions.append(p)
				else:
					found.append(p)
	var newest := func(a, b): return str(a.get("date", "")) > str(b.get("date", "")) \
		or (str(a.get("date", "")) == str(b.get("date", "")) and str(a.get("id", "")).naturalnocasecmp_to(str(b.get("id", ""))) > 0)
	found.sort_custom(newest)
	versions.sort_custom(newest)
	# (the unpublished changes: scanned on a worker thread - a walk over the
	# whole project, ~100 ms - and put at the top when ready: _add_pending)
	if _task < 0:
		scanning = true
		_task = WorkerThreadPool.add_task(func(): _add_pending.call_deferred(unpublished()))
	# Patches in no version yet: at the top, before the versions.
	var grouped := {}
	for v in versions:
		for id in v.get("patches", []):
			grouped[str(id)] = true
	for p in found:
		if not grouped.has(str(p.get("id", ""))):
			patches.append(p)
			_parent.append(-1)
	for v in versions:
		var vi := patches.size()
		patches.append(v)
		_parent.append(-1)
		for p in found:
			if str(p.get("id", "")) in v.get("patches", []).map(func(x): return str(x)):
				patches.append(p)
				_parent.append(vi)


## Patch files, parsed, by path: [modified time, data] - 5 MB of JSON (the
## code reviews) read again only when a file changes, not on every visit.
static var _parsed := {}

static func _read(path: String) -> Variant:
	var t := FileAccess.get_modified_time(path)
	if _parsed.has(path) and _parsed[path][0] == t:
		return _parsed[path][1]
	var p = JSON.parse_string(FileAccess.get_file_as_string(path))
	_parsed[path] = [t, p]
	return p


## The unpublished changes, scanned (load_patches): joins the top of the list.
func _add_pending(entry: Dictionary) -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	scanning = false
	if entry.is_empty() or not is_inside_tree():
		return
	if has_meta("talos_parked"):
		_later = entry   # (Talos is on another tool: added when this one shows - talos_shown)
		return
	patches.insert(0, entry)
	_parent = [-1] + _parent.map(func(x): return x if x < 0 else x + 1)
	# Listed at the top; what you're looking at stays (the newest version's
	# infographic, at first) - only its place in the list moves down one.
	current += 1
	_fill_list()
	if current >= 0 and current < _items.size():
		_selecting = true
		_items[current].select(0)
		_selecting = false


var _later := {}

## Talos shows the Patcher again: the unpublished changes found meanwhile.
func talos_shown() -> void:
	if not _later.is_empty():
		var e := _later
		_later = {}
		_add_pending(e)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## What changed since the last published patch (from external/patcher/ - see
## tools/patch.py; only when running from the project): an entry at the top
## of the list with the change log and the changed files. {} if none / no tracking.
const TRACK := "res://external/patcher/"
const TRACKED := ["gd", "tscn", "tres", "gdshader", "json", "md", "cfg", "py", "godot", "txt", "svg",
	"png", "jpg", "jpeg", "webp", "wav", "ogg", "mp3", "ttf", "otf"]

func unpublished() -> Dictionary:
	if not FileAccess.file_exists(TRACK + "manifest.json"):
		return {}
	var man = JSON.parse_string(FileAccess.get_file_as_string(TRACK + "manifest.json"))
	if not man is Dictionary:
		return {}
	var known: Dictionary = man.get("files", {})
	var times: Dictionary = man.get("mtimes", {})
	var now := _tracked_files("res://")
	var files := []
	for p in now:
		var kind := ""
		if not known.has(p):
			kind = "new"
		elif int(times.get(p, 0)) != FileAccess.get_modified_time("res://" + p) and FileAccess.get_md5("res://" + p) != known[p]:
			kind = "modified"
		if kind != "":
			files.append({"path": p, "kind": kind, "explanation": "%s since patch %s." % [kind.capitalize(), man.get("patch", "?")], "hunks": []})
	var here := {}
	for p in now:
		here[p] = true
	for p in known:
		if not here.has(p):
			files.append({"path": p, "kind": "deleted", "explanation": "Deleted since patch %s." % man.get("patch", "?"), "hunks": []})
	var log := FileAccess.get_file_as_string(TRACK + "pending.md")
	var titles := []
	for l in log.split("\n"):
		if l.begins_with("## "):
			titles.append(l.substr(3))
	if files.is_empty() and titles.is_empty():
		return {}
	return {"id": "pending", "pending": true, "title": "Unpublished changes", "date": "not yet a patch",
		"summary": "%d change(s) logged since patch %s, %d file(s) changed: %s. Ask Claude to publish them as a patch entry when you're ready." % [
			titles.size(), man.get("patch", "?"), files.size(), "; ".join(titles) if not titles.is_empty() else "(not logged yet)"],
		"steps": [], "review": {"intro": log, "files": files}}


func _tracked_files(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.get_extension().to_lower() in TRACKED:
			out.append((dir + f).trim_prefix("res://"))
	for sub in d.get_directories():
		if sub.begins_with(".") or sub in ["build", "export", "__pycache__"] or dir + sub + "/" == TRACK:
			continue
		out.append_array(_tracked_files(dir + sub + "/"))
	return out


func _build() -> void:
	var root := TalosNav.wrap(UI.modal(self, ACCENT, Vector2.ZERO, true), "patcher", func(id): TalosNav.go(get_tree(), id))
	var header: HBoxContainer = TalosNav.header("VERSIONS", "every version of the game and its patches: what changed, step by step", ACCENT)[0]
	header.add_child(_btn("Replay", "reload", "R", "Plays this step's animation again.", func(): _view.restart()))
	header.add_child(_btn("Reload patches", "open", "Ctrl+R", "Reads the patch files again (data/patches/).", func():
		load_patches(); _fill_list(); show_patch(newest())))
	header.add_child(EditorIcons.docs_button(self, "patcher"))
	root.add_child(header)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)
	_list = Tree.new()
	_list.custom_minimum_size = Vector2(330, 0)
	_list.focus_mode = Control.FOCUS_NONE
	_list.hide_root = true
	_list.item_selected.connect(func():
		var it := _list.get_selected()
		if it and not _selecting:
			show_patch(int(it.get_metadata(0))))
	_list.tooltip_text = "Every version with its patches, newest first (Up / Down)."
	body.add_child(_list)
	_fill_list()

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	_title = UI.label("", 26, Color(1.0, 0.9, 0.7))
	right.add_child(_title)
	_date = UI.label("", 14, UI.TEXT_DIM)
	right.add_child(_date)
	# The summary: one paragraph.
	var sp := PanelContainer.new()
	var box := NeonTheme.box(Color(ACCENT, 0.5), Color(0.06, 0.05, 0.03, 0.85), 1, 6, 10)
	box.content_margin_left = 14
	box.content_margin_right = 14
	sp.add_theme_stylebox_override("panel", box)
	_summary = UI.label("", 15, Color(0.92, 0.9, 0.85))
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(400, 0)
	sp.add_child(_summary)
	right.add_child(sp)
	# Two views of the patch: the infographic and the code review.
	_tabs = TabBar.new()
	_tabs.add_tab("Infographic")
	_tabs.add_tab("Code review")
	_tabs.focus_mode = Control.FOCUS_NONE
	_tabs.tab_changed.connect(func(_t): _show_tab())
	_tabs.tooltip_text = "Infographic: the change step by step (Tab switches).\nCode review: every changed file, as diffs with explanations."
	right.add_child(_tabs)
	_info_box = VBoxContainer.new()
	_info_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_info_box)
	_review_box = VBoxContainer.new()
	_review_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_review_box.visible = false
	right.add_child(_review_box)
	_build_review()
	# The infographic.
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	nav.add_child(_btn("Previous step", "back", "Left", "The step before (on the first: the last).", func(): turn(-1)))
	_counter = UI.label("", 15, ACCENT)
	nav.add_child(_counter)
	_step_title = UI.label("", 20, Color.WHITE)
	_step_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(_step_title)
	_open_patch = _btn("Open this patch", "open", "Enter", "A version's page: opens the patch it's about.", open_page_patch)
	nav.add_child(_open_patch)
	nav.add_child(_btn("Next step", "forward", "Right / Space", "The next step (on the last: the first).", func(): turn(1)))
	_info_box.add_child(nav)
	_view = PatchView.new()
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.custom_minimum_size = Vector2(800, 420)
	_view.clip_contents = true
	_info_box.add_child(_view)
	_step_text = UI.label("", 15, Color(0.85, 0.88, 0.95))
	_step_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_step_text.custom_minimum_size = Vector2(400, 0)
	_info_box.add_child(_step_text)
	UI.scale_fonts(root, "menu", 1.2)


## The code review: the changed files (with how many lines were added and
## removed) and, for the chosen file, what changed and why, hunk by hunk,
## with the diff itself (+ added in green, - removed in red).
func _build_review() -> void:
	_review_intro = UI.label("", 14, UI.TEXT_DIM)
	_review_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_review_intro.custom_minimum_size = Vector2(400, 0)
	_review_box.add_child(_review_intro)
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 10)
	_review_box.add_child(split)
	# Playing a sound asset (shown for sounds only).
	_asset_bar = HBoxContainer.new()
	_asset_bar.add_theme_constant_override("separation", 8)
	_asset_bar.visible = false
	_asset_bar.add_child(_btn("Play the sound", "play", "", "Plays the sound asset (again to restart).", func():
		if _player.stream: _player.play()))
	_asset_bar.add_child(_btn("Stop", "stop", "", "Stops the sound.", func(): _player.stop()))
	_asset_info = UI.label("", 14, UI.TEXT_DIM)
	_asset_bar.add_child(_asset_info)
	_review_box.add_child(_asset_bar)
	_review_box.move_child(_asset_bar, 1)
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_files = ItemList.new()
	_files.custom_minimum_size = Vector2(320, 0)
	_files.focus_mode = Control.FOCUS_NONE
	_files.item_selected.connect(func(i): show_file(i))
	_files.tooltip_text = "The files this patch changed: lines added / removed."
	split.add_child(_files)
	_mono = SystemFont.new()
	_mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Noto Sans Mono", "Liberation Mono", "Consolas", "Menlo", "Courier New", "monospace"])
	_review = RichTextLabel.new()
	_review.bbcode_enabled = true
	_review.selection_enabled = true
	_review.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_review.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_review.add_theme_font_override("mono_font", _mono)
	_review.add_theme_font_size_override("mono_font_size", 13)
	_review.add_theme_constant_override("line_separation", 4)   # (each diff line's background mustn't hide the underscores above)
	_review.add_theme_font_size_override("normal_font_size", 15)
	_review.add_theme_font_size_override("bold_font_size", 17)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.035, 0.06)
	bg.set_content_margin_all(12)
	_review.add_theme_stylebox_override("normal", bg)
	split.add_child(_review)
	_bubbles = Bubbles.new()
	_bubbles.review = _review
	_bubbles.font = _mono
	_review.add_child(_bubbles)
	_bubbles.set_anchors_preset(Control.PRESET_FULL_RECT)


func _show_tab() -> void:
	_info_box.visible = _tabs.current_tab == 0
	_review_box.visible = _tabs.current_tab == 1


func _fill_review() -> void:
	var rv: Dictionary = patches[current].get("review", {})
	_tabs.set_tab_disabled(1, rv.is_empty())
	if rv.is_empty() and _tabs.current_tab == 1:
		_tabs.current_tab = 0
	_review_intro.text = str(rv.get("intro", ""))
	_files.clear()
	_rows = []
	var files: Array = rv.get("files", [])
	var assets := 0
	for f in files:
		if _asset_kind(f["path"]) != "text":
			assets += 1
	# Code first, then the other text files, then the assets (each group in
	# the review's order); the gallery of every asset heads the assets.
	var order: Array = range(files.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var ga := _file_group(files[a]["path"])
		var gb := _file_group(files[b]["path"])
		return ga < gb or (ga == gb and a < b))
	var gallery := assets > 1
	for k in order:
		var f: Dictionary = files[k]
		if gallery and _file_group(f["path"]) == 2:   # a gallery of every asset
			gallery = false
			var g := _files.add_item("All assets  (%d)" % assets)
			_files.set_item_custom_fg_color(g, Color(1.0, 0.8, 0.45))
			_files.set_item_tooltip(g, "Every image, sound and font in this change, together.")
			_rows.append(-1)
		var kind := _asset_kind(f["path"])
		var label := "%s   +%d  -%d" % [str(f["path"]).get_file(), int(f.get("added", 0)), int(f.get("removed", 0))]
		if f.get("hunks", []).is_empty() and f.has("kind"):
			label = "%s   (%s%s)" % [str(f["path"]).get_file(), f["kind"], "" if kind == "text" else ", " + kind]
		var i := _files.add_item(label)
		_files.set_item_tooltip(i, "%s\n%s" % [f["path"], f.get("explanation", "")])
		_rows.append(k)
	_review.clear()
	_bubbles.clear()
	_show_asset_bar(false)
	if patches[current].get("pending", false):
		# Unpublished changes: the change log in full (pick a file to see it).
		_review_intro.text = "Changed since the last patch, not yet published - the change log, and the files (new, modified, deleted): pick one to see it. It becomes a patch entry when you ask Claude to publish it."
		_review.append_text("[color=#dde3ee]%s[/color]" % _esc(str(rv.get("intro", ""))))
	elif _files.item_count > 0:
		show_file(0)


## Where a file goes in the review's list: 0 code, 1 other text, 2 assets.
func _file_group(path: String) -> int:
	if _asset_kind(path) != "text":
		return 2
	return 0 if path.get_extension().to_lower() in CODE else 1


## What a file is, for viewing: image, sound, font or text.
func _asset_kind(path: String) -> String:
	var e := path.get_extension().to_lower()
	if e in IMAGES:
		return "image"
	if e in SOUNDS:
		return "sound"
	if e in FONTS:
		return "font"
	return "text"


func _abs(path: String) -> String:
	return ProjectSettings.globalize_path("res://" + path)


## An image asset as a texture, read from the file itself (assets in external/
## aren't imported), on a checkerboard so transparency shows. null if missing.
func _image_texture(path: String, checker := true) -> Texture2D:
	var key := "%s|%s" % [path, checker]
	if _tex_cache.has(key):
		return _tex_cache[key]
	if not FileAccess.file_exists("res://" + path):
		return null
	var img := Image.new()
	var err: int
	if path.get_extension().to_lower() == "svg":
		err = img.load_svg_from_string(FileAccess.get_file_as_string("res://" + path))
	else:
		err = img.load(_abs(path))
	if err != OK or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	if checker:
		var bg := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		bg.fill(Color(0.2, 0.21, 0.25))
		var c := 16
		for y in range(0, img.get_height(), c):
			for x in range(0, img.get_width(), c):
				if (x / c + y / c) % 2 == 0:
					bg.fill_rect(Rect2i(x, y, c, c), Color(0.27, 0.28, 0.33))
		bg.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
		img = bg
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## A size that fits `box` (small images grow up to 2x, big ones shrink).
func _fit(size: Vector2, box: Vector2) -> Vector2:
	return size * minf(2.0, minf(box.x / size.x, box.y / size.y))


func _show_asset_bar(on: bool, info := "") -> void:
	_asset_bar.visible = on
	_asset_info.text = info
	if not on:
		_player.stop()


func _file_bytes(path: String) -> String:
	var fa := FileAccess.open("res://" + path, FileAccess.READ)
	if fa == null:
		return "?"
	var n := fa.get_length()
	return "%.1f MB" % (n / 1048576.0) if n > 1048576 else "%d KB" % maxi(1, n / 1024)


## Shows a list row: one changed file (its explanation, then the asset itself
## or every hunk - title, note, diff), or the gallery of all assets.
func show_file(row: int) -> void:
	var files: Array = patches[current].get("review", {}).get("files", [])
	if row < 0 or row >= _rows.size():
		return
	_files.select(row)
	_review.clear()
	_bubbles.clear()
	_show_asset_bar(false)
	var i: int = _rows[row]
	if i < 0:
		_show_gallery(files)
		return
	var f: Dictionary = files[i]
	var b := "[font_size=20][color=#ffcf7a][b]%s[/b][/color][/font_size]   " % _esc(f["path"])
	if f.get("hunks", []).is_empty() and _asset_kind(f["path"]) != "text":
		b += "[color=#8a93a6]%s %s[/color]\n" % [f.get("kind", ""), _asset_kind(f["path"])]
	else:
		b += "[color=#6fd36f]+%d[/color]  [color=#ff6b5e]-%d[/color]\n" % [int(f.get("added", 0)), int(f.get("removed", 0))]
	b += "[color=#dde3ee]%s[/color]\n\n" % _esc(str(f.get("explanation", "")))
	if f.get("hunks", []).is_empty():
		_review.append_text(b)
		_show_asset(f)
		_review.scroll_to_line(0)
		return
	var n := 1
	var code: Dictionary = {}   # paragraph -> the code line shown in it (the others: full-width text)
	var points: Array = []      # [paragraph, bubble text]
	for h in f.get("hunks", []):
		b += "[color=#7fd8ff][b]%d.  %s[/b][/color]   [color=#8a93a6]+%d -%d[/color]\n" % [n, _esc(h["title"]), int(h.get("added", 0)), int(h.get("removed", 0))]
		b += "[color=#cfd6e4]%s[/color]\n" % _esc(str(h.get("note", "")))
		b += "[code]"
		var diff := str(h["diff"]).split("\n")
		var first := b.count("\n")
		for k in diff.size():
			code[first + k] = diff[k].replace("\t", "    ")
		for bu in h.get("bubbles", []):
			var at := bubble_line(diff, bu)
			if at >= 0:
				points.append([first + at, str(bu.get("text", ""))])
		for l in diff:
			var line := _esc(l.replace("\t", "    "))
			match l.left(1):
				"+":
					b += "[bgcolor=#0f3a1c][color=#9df5a6]%s[/color][/bgcolor]\n" % line
				"-":
					b += "[bgcolor=#45161a][color=#ffaaa2]%s[/color][/bgcolor]\n" % line
				"@":
					b += "[color=#8ab4ff]%s[/color]\n" % line
				_:
					b += "[color=#7d8596]%s[/color]\n" % line
		b += "[/code]\n"
		n += 1
	_review.append_text(b)
	_review.scroll_to_line(0)
	_bubbles.show_points(code, points)


## The diff line a bubble points at: the first containing its "at" (added
## lines first), or its "line" (an index in the diff); -1: none.
static func bubble_line(diff: PackedStringArray, bubble: Dictionary) -> int:
	if bubble.has("line"):
		var k := int(bubble["line"])
		return k if k >= 0 and k < diff.size() else -1
	var at := str(bubble.get("at", ""))
	if at.is_empty():
		return -1
	for pass_ in 2:
		for k in diff.size():
			if (pass_ == 1 or diff[k].begins_with("+")) and not diff[k].begins_with("@@") and diff[k].contains(at):
				return k
	return -1


## The asset of a file without a diff: the picture, a sound to play, a font
## sample, or the text itself.
func _show_asset(f: Dictionary) -> void:
	var path: String = f["path"]
	if f.get("kind", "") == "deleted":
		_review.append_text("[color=#ff9a8a](deleted - no longer in the project)[/color]\n")
		return
	if not FileAccess.file_exists("res://" + path):
		_review.append_text("[color=#ff9a8a](no longer in the project - it was moved or deleted since)[/color]\n")
		return
	match _asset_kind(path):
		"image":
			var tex := _image_texture(path)
			if tex == null:
				_review.append_text("[color=#ff9a8a](couldn't read the image)[/color]\n")
				return
			_review.append_text("[color=#8a93a6]%d x %d px  ·  %s[/color]\n" % [tex.get_width(), tex.get_height(), _file_bytes(path)])
			var sz := _fit(Vector2(tex.get_size()), Vector2(maxf(200.0, _review.size.x - 40.0), 520.0))
			_review.add_image(tex, int(sz.x), int(sz.y))
			_review.add_text("\n")
		"sound":
			var stream := _load_sound(path)
			_player.stream = stream
			var info := "%s  ·  %s" % [path.get_file(), _file_bytes(path)]
			if stream:
				info += "  ·  %.1f s" % stream.get_length()
			_show_asset_bar(stream != null, info)
			_review.append_text("[color=#cfd6e4]A sound: play it with the button above.[/color]\n" if stream else "[color=#ff9a8a](couldn't read the sound)[/color]\n")
		"font":
			var font := FontFile.new()
			if font.load_dynamic_font(_abs(path)) != OK:
				_review.append_text("[color=#ff9a8a](couldn't read the font)[/color]\n")
				return
			for fs in [14, 22, 34]:
				_review.push_font(font, fs)
				_review.add_text("Sphinx of black quartz, judge my vow - 0123456789\n")
				_review.pop()
		_:
			var text := FileAccess.get_file_as_string("res://" + path)
			var lines := text.split("\n")
			var shown := "\n".join(lines.slice(0, 400))
			_review.append_text("[code][color=#cfd6e4]%s[/color][/code]" % _esc(shown.replace("\t", "    ")))
			if lines.size() > 400:
				_review.append_text("\n[color=#8a93a6](... %d more lines)[/color]" % (lines.size() - 400))


func _load_sound(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(_abs(path))
		"mp3":
			var m := AudioStreamMP3.new()
			m.data = FileAccess.get_file_as_bytes("res://" + path)
			return m
		"wav":
			return AudioStreamWAV.load_from_file(_abs(path))
	return null


## Every asset of the change together: pictures as thumbnails with their
## names; sounds and fonts listed (pick one to play / see it).
func _show_gallery(files: Array) -> void:
	_review.append_text("[font_size=20][color=#ffcf7a][b]All assets[/b][/color][/font_size]\n[color=#8a93a6]Pick one in the list to see it full size (or to play a sound).[/color]\n\n")
	var cols := maxi(2, int((_review.size.x - 40.0) / 190.0))
	_review.push_table(cols)
	var others := []
	for f in files:
		if _asset_kind(f["path"]) != "image":
			if _asset_kind(f["path"]) != "text":
				others.append(f)
			continue
		_review.push_cell()
		var tex := _image_texture(f["path"])
		if tex:
			var sz := _fit(Vector2(tex.get_size()), Vector2(170, 170))
			_review.add_image(tex, int(sz.x), int(sz.y))
		else:
			_review.append_text("[color=#ff9a8a](missing)[/color]")
		_review.append_text("\n[font_size=12][color=#cfd6e4]%s[/color][/font_size]\n " % _esc(str(f["path"]).get_file()))
		_review.pop()
	_review.pop()
	for f in others:
		_review.append_text("\n[color=#cfd6e4]%s  (%s)[/color]" % [_esc(f["path"]), _asset_kind(f["path"])])


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func is_version(i: int) -> bool:
	return i >= 0 and i < patches.size() and patches[i].get("kind", "") == "version"


func _fill_list() -> void:
	_list.clear()
	_items = []
	var root := _list.create_item()
	for i in patches.size():
		var p: Dictionary = patches[i]
		var parent: TreeItem = root if _parent[i] < 0 else _items[_parent[i]]
		var it := _list.create_item(parent)
		if p.get("pending", false):
			it.set_text(0, "●  %s" % p["title"])
			it.set_custom_color(0, Color(1.0, 0.75, 0.35))
		elif is_version(i):
			it.set_text(0, "Version %s  ·  %s" % [p.get("id", "?"), p.get("title", "")])
			it.set_custom_color(0, Color(1.0, 0.86, 0.5))
		else:
			it.set_text(0, "%s  ·  %s" % [p.get("id", ""), p.get("title", p.get("id", "?"))])
		it.set_metadata(0, i)
		it.set_tooltip_text(0, "%s\n%s" % [p.get("title", ""), p.get("summary", "")])
		_items.append(it)


func show_patch(i: int) -> void:
	if i < 0 or i >= patches.size():
		return
	current = i
	if i < _items.size():
		_selecting = true
		_items[i].select(0)
		_list.scroll_to_item(_items[i])
		_selecting = false
	var p: Dictionary = patches[i]
	_title.text = ("Version %s  ·  %s" % [p.get("id", ""), p.get("title", "")]) if is_version(i) else str(p.get("title", ""))
	if p.get("pending", false):
		_date.text = "not published yet  ·  tools/patch.py status for the details"
	elif is_version(i):
		_date.text = "%s  ·  version %s  ·  %d patches  ·  a page for each" % [p.get("date", ""), p.get("id", ""), p.get("patches", []).size()]
	else:
		var v := "" if _parent[i] < 0 else "  ·  in version %s" % patches[_parent[i]].get("id", "")
		_date.text = "%s  ·  patch %s  ·  %d steps%s" % [p.get("date", ""), p.get("id", ""), p["steps"].size(), v]
	_summary.text = str(p.get("summary", ""))
	_fill_review()
	_tabs.set_tab_disabled(0, p["steps"].is_empty())
	if p["steps"].is_empty():
		_tabs.current_tab = 1   # (unpublished changes: no infographic yet)
	else:
		_tabs.current_tab = 0   # (an entry always opens on its infographic, not the code)
	_show_tab()
	go_step(0, true)


## Shows step i (clamped to the steps there are). Past the last step (or
## before the first) nothing happens - the step stays as it is, its diagram
## isn't replayed; force: show it anyway (a newly opened entry).
func go_step(i: int, force := false) -> void:
	if current < 0:
		return
	var steps: Array = patches[current]["steps"]
	if not force and not steps.is_empty() and clampi(i, 0, steps.size() - 1) == step:
		return
	if steps.is_empty():
		_open_patch.visible = false
		_counter.text = ""
		_step_title.text = ""
		_step_text.text = ""
		_view.show_diagram([])
		return
	step = clampi(i, 0, steps.size() - 1)
	var s: Dictionary = steps[step]
	if is_version(current):
		_counter.text = "Page %d / %d%s" % [step + 1, steps.size(), ("  ·  patch %s" % s["patch"]) if s.has("patch") else ""]
	else:
		_counter.text = "Step %d / %d" % [step + 1, steps.size()]
	_open_patch.visible = is_version(current) and _page_patch() >= 0
	_step_title.text = str(s.get("title", ""))
	_step_text.text = str(s.get("text", ""))
	_view.show_diagram(s.get("diagram", []))


## Next (by 1) / Previous (by -1) step, going round: Next on the last step
## shows the first, Previous on the first the last.
func turn(by: int) -> void:
	if current >= 0 and not patches[current]["steps"].is_empty():
		go_step(posmod(step + by, patches[current]["steps"].size()))


## The entry of the patch the version's current page is about (-1: none).
func _page_patch() -> int:
	if not is_version(current):
		return -1
	var s: Dictionary = patches[current]["steps"][step]
	for k in patches.size():
		if not is_version(k) and not patches[k].get("pending", false) and str(patches[k].get("id", "")) == str(s.get("patch", "")):
			return k
	return -1


func open_page_patch() -> void:
	var k := _page_patch()
	if k >= 0:
		show_patch(k)


func _back() -> void:
	TalosNav.go(get_tree(), "menu")   # (Esc: as the rail's Exit)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	match k.keycode:
		KEY_RIGHT, KEY_SPACE:
			turn(1)
		KEY_LEFT:
			turn(-1)
		KEY_DOWN:
			show_patch(current + 1)
		KEY_UP:
			show_patch(current - 1)
		KEY_R:
			if k.ctrl_pressed:
				load_patches(); _fill_list(); show_patch(newest())
			else:
				_view.restart()
		KEY_ENTER, KEY_KP_ENTER:
			open_page_patch()
		KEY_TAB:
			_tabs.current_tab = 1 - _tabs.current_tab if not _tabs.is_tab_disabled(1) else 0
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()   # (before: leaving frees the scene)
			_back()
			return
		KEY_F1:
			EditorDocs.open(self, "patcher", EditorDocs.FILE)
		_:
			return
	get_viewport().set_input_as_handled()


func _btn(name: String, icon: String, keys: String, help: String, cb: Callable) -> Button:
	var b := UI.button("", cb, 14)
	b.focus_mode = Control.FOCUS_NONE
	return EditorIcons.dress(b, icon, EditorIcons.tip(name, keys, help))


## Draws one step's diagram: vector elements on a 1000 x 560 canvas scaled
## to fit, each fading / sliding in (arrows draw themselves, bars fill),
## pulsing ones glowing. Elements ({"t": kind, ...}, positions in canvas px;
## colours "#rrggbb" or a name from COLORS):
##   box     rect [x,y,w,h], fill, stroke, label, size, color, r (corner)
##   text    at [x,y], text (\n for lines), size, color, align left/center/right
##   arrow   from, to, color, width, label, bend (sideways bow, px), dashed
##   circle  at, r, fill, stroke, label
##   grid    rect, cols, rows, fill, stroke, cells [[col,row,colour]...]
##   iso     at (centre), w (width; height w / 2), n (grid lines), fill, stroke,
##           marks [[u,v,colour,size,label]...], areas [[u,v,du,dv,colour,dashed]...] (0..1)
##   bar     rect, value 0..1, color, label, track
##   badge   at (centre), text, color, size
##   poly    points [[x,y]...], fill, stroke, closed
## Any element: delay (s), pulse (true).
class PatchView extends Control:
	const W := 1000.0
	const H := 560.0
	## The smallest text in a diagram (its units): shown at 86% at 1920 x 1080
	## (the Versions page), that's 14 px - never under Settings.MIN_FONT.
	const MIN_TEXT := 16
	const COLORS := {"cyan": Color(0.35, 0.85, 1.0), "gold": Color(1.0, 0.78, 0.3), "green": Color(0.45, 0.9, 0.45),
		"red": Color(0.95, 0.35, 0.3), "blue": Color(0.35, 0.55, 1.0), "purple": Color(0.7, 0.5, 1.0),
		"white": Color(0.95, 0.95, 0.97), "dim": Color(0.55, 0.6, 0.7), "dark": Color(0.08, 0.1, 0.16),
		"panel": Color(0.11, 0.14, 0.22), "land": Color(0.3, 0.55, 0.3), "forest": Color(0.18, 0.42, 0.25),
		"sea": Color(0.15, 0.35, 0.6), "sand": Color(0.85, 0.75, 0.5), "stone": Color(0.85, 0.72, 0.55)}
	var elements: Array = []
	var t := 0.0
	var _font: Font

	func _ready() -> void:
		_font = ThemeDB.fallback_font

	func show_diagram(els: Array) -> void:
		elements = els
		restart()

	func restart() -> void:
		t = 0.0
		queue_redraw()

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _col(v: Variant, fallback: Color) -> Color:
		if v == null:
			return fallback
		if v is Color:
			return v
		var s := str(v)
		if COLORS.has(s):
			return COLORS[s]
		return Color.from_string(s, fallback)

	func _p(v: Variant) -> Vector2:
		return Vector2(float(v[0]), float(v[1]))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.045, 0.08))
		# A faint blueprint grid behind everything.
		var k := minf(size.x / W, size.y / H)
		var off := (size - Vector2(W, H) * k) / 2.0
		draw_set_transform(off, 0.0, Vector2(k, k))
		for x in range(0, int(W) + 1, 40):
			draw_line(Vector2(x, 0), Vector2(x, H), Color(0.3, 0.5, 0.8, 0.06), 1.0)
		for y in range(0, int(H) + 1, 40):
			draw_line(Vector2(0, y), Vector2(W, y), Color(0.3, 0.5, 0.8, 0.06), 1.0)
		for i in elements.size():
			var e: Dictionary = elements[i]
			var delay := float(e.get("delay", 0.15 + i * 0.12))
			var a := clampf((t - delay) / 0.4, 0.0, 1.0)
			if a <= 0.0:
				continue
			var ease := 1.0 - pow(1.0 - a, 3.0)
			var glow := 0.0
			if e.get("pulse", false):
				glow = 0.5 + 0.5 * sin((t - delay) * 4.0)
			draw_set_transform(off + Vector2(0, (1.0 - ease) * 14.0 * k), 0.0, Vector2(k, k))
			_element(e, ease, glow)
		draw_set_transform(Vector2.ZERO)

	func _element(e: Dictionary, a: float, glow: float) -> void:
		match str(e.get("t", "")):
			"box":
				var r := Rect2(_p(e["rect"]), Vector2(float(e["rect"][2]), float(e["rect"][3])))
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color(_col(e.get("fill"), COLORS["panel"]), _col(e.get("fill"), COLORS["panel"]).a * a)
				var st := _col(e.get("stroke"), COLORS["cyan"])
				sb.border_color = Color(st.lightened(0.3 * glow), a)
				sb.set_border_width_all(int(e.get("border", 2)) + (1 if glow > 0.5 else 0))
				sb.set_corner_radius_all(int(e.get("r", 10)))
				sb.anti_aliasing = true
				if glow > 0.0:
					sb.shadow_color = Color(st, 0.35 * glow * a)
					sb.shadow_size = 12
				draw_style_box(sb, r)
				if e.has("label"):
					_text_in(str(e["label"]), r, text_size(e, 18), Color(_col(e.get("color"), COLORS["white"]), a))
			"text":
				var p := _p(e["at"])
				_lines(str(e["text"]), p, text_size(e, 18), Color(_col(e.get("color"), COLORS["white"]), a), str(e.get("align", "left")))
			"arrow":
				var f := _p(e["from"])
				var to := _p(e["to"])
				var c := Color(_col(e.get("color"), COLORS["cyan"]).lightened(0.3 * glow), a)
				var w := float(e.get("width", 3.0))
				var bend := float(e.get("bend", 0.0))
				var mid := (f + to) / 2.0 + (to - f).orthogonal().normalized() * bend
				var pts := PackedVector2Array()
				var n := 24
				for i in int(n * a) + 1:
					var u := float(i) / n
					pts.append(f.lerp(mid, u).lerp(mid.lerp(to, u), u))
				if pts.size() >= 2:
					if e.get("dashed", false):
						for i in range(0, pts.size() - 1, 2):
							draw_line(pts[i], pts[i + 1], c, w, true)
					else:
						draw_polyline(pts, c, w, true)
					if a >= 1.0:
						var tip := pts[-1]
						var dir := (tip - pts[-2]).normalized()
						var head := 6.0 + w * 2.5
						draw_colored_polygon(PackedVector2Array([tip + dir * 2.0, tip - dir * head + dir.orthogonal() * head * 0.6,
							tip - dir * head - dir.orthogonal() * head * 0.6]), c)
				if e.has("label") and a >= 1.0:
					_lines(str(e["label"]), arrow_label_at(e), text_size(e, 15), Color(_col(e.get("label_color"), COLORS["white"]), a), "center")
			"circle":
				var p := _p(e["at"])
				var r := float(e.get("r", 10)) * (1.0 + 0.15 * glow)
				if glow > 0.0:
					draw_circle(p, r * 1.8, Color(_col(e.get("fill"), COLORS["gold"]), 0.18 * glow * a))
				draw_circle(p, r, Color(_col(e.get("fill"), COLORS["gold"]), a))
				if e.has("stroke"):
					draw_arc(p, r, 0, TAU, 32, Color(_col(e["stroke"], Color.WHITE), a), 2.0, true)
				if e.has("label"):
					_lines(str(e["label"]), _p(e["at"]) + Vector2(0, float(e.get("r", 10)) + 16), text_size(e, 14), Color(COLORS["white"], a), "center")
			"grid":
				var r := Rect2(_p(e["rect"]), Vector2(float(e["rect"][2]), float(e["rect"][3])))
				var cols := int(e.get("cols", 4))
				var rows := int(e.get("rows", 4))
				var cw := r.size.x / cols
				var ch := r.size.y / rows
				draw_rect(r, Color(_col(e.get("fill"), COLORS["dark"]), a))
				for c in e.get("cells", []):
					draw_rect(Rect2(r.position + Vector2(float(c[0]) * cw, float(c[1]) * ch), Vector2(cw, ch)).grow(-1), Color(_col(c[2], COLORS["green"]), a))
				var gs := Color(_col(e.get("stroke"), COLORS["dim"]), 0.35 * a)
				for i in cols + 1:
					draw_line(r.position + Vector2(i * cw, 0), r.position + Vector2(i * cw, r.size.y), gs, 1.0)
				for j in rows + 1:
					draw_line(r.position + Vector2(0, j * ch), r.position + Vector2(r.size.x, j * ch), gs, 1.0)
			"iso":
				var c := _p(e["at"])
				var w := float(e.get("w", 200)) * (0.85 + 0.15 * a)
				var dx := Vector2(w / 2.0, w / 4.0)    # u axis (to the right and down)
				var dy := Vector2(-w / 2.0, w / 4.0)   # v axis (to the left and down)
				var top := c - Vector2(0, w / 4.0)
				var uv := func(u: float, v: float) -> Vector2: return top + dx * u + dy * v
				draw_colored_polygon(PackedVector2Array([uv.call(0, 0), uv.call(1, 0), uv.call(1, 1), uv.call(0, 1)]), Color(_col(e.get("fill"), COLORS["land"]), a))
				var n := int(e.get("n", 0))
				var gl := Color(_col(e.get("stroke"), Color(0, 0, 0)), 0.25 * a)
				for i in range(1, n):
					var f := float(i) / n
					draw_line(uv.call(f, 0), uv.call(f, 1), gl, 1.0, true)
					draw_line(uv.call(0, f), uv.call(1, f), gl, 1.0, true)
				for ar in e.get("areas", []):
					var u0 := float(ar[0])
					var v0 := float(ar[1])
					var u1 := u0 + float(ar[2])
					var v1 := v0 + float(ar[3])
					var poly := PackedVector2Array([uv.call(u0, v0), uv.call(u1, v0), uv.call(u1, v1), uv.call(u0, v1)])
					var col := _col(ar[4], COLORS["cyan"])
					if ar.size() > 5 and ar[5]:
						var closed := poly + PackedVector2Array([poly[0]])
						for i in 4:
							_dash(closed[i], closed[i + 1], Color(col, a), 2.0)
					else:
						draw_colored_polygon(poly, Color(col, col.a * 0.35 * a))
						draw_polyline(poly + PackedVector2Array([poly[0]]), Color(col.lightened(0.3 * glow), a), 2.0, true)
				draw_polyline(PackedVector2Array([uv.call(0, 0), uv.call(1, 0), uv.call(1, 1), uv.call(0, 1), uv.call(0, 0)]), Color(_col(e.get("stroke"), COLORS["cyan"]), 0.8 * a), 2.0, true)
				for m in e.get("marks", []):
					var p: Vector2 = uv.call(float(m[0]), float(m[1]))
					var sz := float(m[3]) if m.size() > 3 else 6.0
					draw_circle(p, sz, Color(_col(m[2], COLORS["gold"]), a))
					draw_arc(p, sz, 0, TAU, 20, Color(0, 0, 0, 0.5 * a), 1.5, true)
					if m.size() > 4:
						_lines(str(m[4]), p + Vector2(0, -sz - 8), MIN_TEXT, Color(COLORS["white"], a), "center")
			"bar":
				var r := Rect2(_p(e["rect"]), Vector2(float(e["rect"][2]), float(e["rect"][3])))
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color(_col(e.get("track"), Color(0.15, 0.17, 0.25)), a)
				sb.set_corner_radius_all(int(r.size.y / 2))
				sb.anti_aliasing = true
				draw_style_box(sb, r)
				var fill := r
				fill.size.x = maxf(r.size.y, r.size.x * clampf(float(e.get("value", 0.5)), 0.0, 1.0) * a)
				var sf := sb.duplicate()
				sf.bg_color = Color(_col(e.get("color"), COLORS["green"]).lightened(0.25 * glow), a)
				draw_style_box(sf, fill)
				if e.has("label"):
					_lines(str(e["label"]), r.position + Vector2(14, r.size.y / 2.0 + 6), text_size(e, 15), Color(COLORS["white"], a), "left", true)
			"badge":
				var p := _p(e["at"])
				var fs := text_size(e, 16)
				var tw := _font.get_string_size(str(e["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var r := Rect2(p - Vector2(tw / 2.0 + 16, fs * 0.5 + 9), Vector2(tw + 32, fs + 18))
				var sb := StyleBoxFlat.new()
				var c := _col(e.get("color"), COLORS["gold"])
				sb.bg_color = Color(c.darkened(0.6), 0.95 * a)
				sb.border_color = Color(c.lightened(0.3 * glow), a)
				sb.set_border_width_all(2)
				sb.set_corner_radius_all(int(r.size.y / 2))
				sb.anti_aliasing = true
				draw_style_box(sb, r)
				_lines(str(e["text"]), Vector2(p.x, p.y + fs * 0.35), fs, Color(c.lightened(0.5), a), "center")
			"poly":
				var pts := PackedVector2Array()
				for q in e["points"]:
					pts.append(_p(q))
				if e.has("fill"):
					draw_colored_polygon(pts, Color(_col(e["fill"], COLORS["panel"]), a))
				if e.has("stroke"):
					if e.get("closed", true):
						pts.append(pts[0])
					draw_polyline(pts, Color(_col(e["stroke"], COLORS["cyan"]), a), float(e.get("width", 2.0)), true)

	## An element's text size (its `size`, else `default`), never under MIN_TEXT.
	static func text_size(e: Dictionary, default: int) -> int:
		return maxi(MIN_TEXT, int(e.get("size", default)))

	## Where an arrow's label goes: above the middle of its curve.
	static func arrow_label_at(e: Dictionary) -> Vector2:
		var f := Vector2(float(e["from"][0]), float(e["from"][1]))
		var to := Vector2(float(e["to"][0]), float(e["to"][1]))
		var mid := (f + to) / 2.0 + (to - f).orthogonal().normalized() * float(e.get("bend", 0.0))
		return (f.lerp(mid, 0.5)).lerp(mid.lerp(to, 0.5), 0.5) + Vector2(0, -12)

	## The rectangles a line-by-line text covers (as _lines draws it).
	static func _line_rects(font: Font, s: String, at: Vector2, fs: int, align: String) -> Array:
		var out := []
		var y := at.y
		for l in s.split("\n"):
			var w := font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var x := at.x - (w / 2.0 if align == "center" else (w if align == "right" else 0.0))
			if w > 2.0:   # (an empty line covers nothing)
				out.append(Rect2(x, y - font.get_ascent(fs), w, font.get_ascent(fs) + font.get_descent(fs)))
			y += fs * 1.25
		return out

	## What's wrong with a diagram's text, at the sizes it's drawn (MIN_TEXT
	## and up): a label wider or taller than its box, text off the canvas,
	## two elements' texts over each other. [] - all readable.
	static func lint(els: Array, font: Font) -> Array:
		var out := []
		var texts := []   # [element index, rect]
		for i in els.size():
			var e: Dictionary = els[i]
			var tag := "%d %s" % [i, str(e.get("t", ""))]
			match str(e.get("t", "")):
				"box":
					if str(e.get("label", "")) == "":
						continue   # (a frame round other things)
					var r := Rect2(float(e["rect"][0]), float(e["rect"][1]), float(e["rect"][2]), float(e["rect"][3]))
					var fs := text_size(e, 18)
					var lines := str(e["label"]).split("\n")
					for l in lines:
						if font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x - 12.0:
							out.append("%s: \"%s\" wider than its box (%d)" % [tag, l, r.size.x])
					if lines.size() * fs * 1.25 > r.size.y - 4.0:
						out.append("%s: %d lines taller than its box (%d)" % [tag, lines.size(), r.size.y])
					# (its lines, as _text_in places them - a box can frame other things)
					var lh := fs * 1.25
					var y := r.get_center().y - lh * lines.size() / 2.0 + fs * 0.95
					for l in lines:
						var w := font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
						if w > 2.0:
							texts.append([i, Rect2(r.get_center().x - w / 2.0, y - font.get_ascent(fs), w, font.get_ascent(fs) + font.get_descent(fs))])
						y += lh
					continue
				"text":
					for r in _line_rects(font, str(e["text"]), Vector2(float(e["at"][0]), float(e["at"][1])), text_size(e, 18), str(e.get("align", "left"))):
						texts.append([i, r])
				"arrow":
					if e.has("label"):
						for r in _line_rects(font, str(e["label"]), arrow_label_at(e), text_size(e, 15), "center"):
							texts.append([i, r])
				"circle":
					if e.has("label"):
						var at := Vector2(float(e["at"][0]), float(e["at"][1])) + Vector2(0, float(e.get("r", 10)) + 16)
						for r in _line_rects(font, str(e["label"]), at, text_size(e, 14), "center"):
							texts.append([i, r])
				"bar":
					if e.has("label"):
						var at := Vector2(float(e["rect"][0]) + 14, float(e["rect"][1]) + float(e["rect"][3]) / 2.0 + 6)
						for r in _line_rects(font, str(e["label"]), at, text_size(e, 15), "left"):
							texts.append([i, r])
				"badge":
					var fs := text_size(e, 16)
					var p := Vector2(float(e["at"][0]), float(e["at"][1]))
					var tw := font.get_string_size(str(e["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					texts.append([i, Rect2(p - Vector2(tw / 2.0 + 16, fs * 0.5 + 9), Vector2(tw + 32, fs + 18))])
		var canvas := Rect2(0, 0, W, H)
		for a in texts:
			if not canvas.encloses(a[1].grow(-1.0)):
				out.append("%d %s: text off the canvas %s" % [a[0], str(els[a[0]].get("t", "")), a[1]])
		for x in texts.size():
			for y in range(x + 1, texts.size()):
				var p: Array = texts[x]
				var q: Array = texts[y]
				if p[0] != q[0] and p[1].grow(-1.0).intersects(q[1].grow(-1.0)):
					out.append("%d %s and %d %s: texts over each other" % [p[0], str(els[p[0]].get("t", "")), q[0], str(els[q[0]].get("t", ""))])
		return out

	func _dash(a: Vector2, b: Vector2, c: Color, w: float) -> void:
		var n := maxi(2, int(a.distance_to(b) / 10.0))
		for i in range(0, n, 2):
			draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), c, w, true)

	## Text centred in a rectangle (several lines).
	func _text_in(s: String, r: Rect2, fs: int, c: Color) -> void:
		var lines := s.split("\n")
		var lh := fs * 1.25
		var y := r.get_center().y - lh * lines.size() / 2.0 + fs * 0.95
		for l in lines:
			draw_string(_font, Vector2(r.position.x, y), l, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, c)
			y += lh

	func _lines(s: String, at: Vector2, fs: int, c: Color, align: String, outline := false) -> void:
		var y := at.y
		for l in s.split("\n"):
			var w := _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var x := at.x
			if align == "center":
				x -= w / 2.0
			elif align == "right":
				x -= w
			if outline:   # (readable over any fill)
				draw_string_outline(_font, Vector2(x, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.7 * c.a))
			draw_string(_font, Vector2(x, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
			y += fs * 1.25


## Explanation bubbles over the code review: each in the empty space beside
## the code (to the right of short lines, never over code or text), as near
## its line as there's room, with an arrow to the end of that line (which is
## outlined). Placed in the text's coordinates, so they scroll with it; laid
## out again when the viewer is resized. A bubble with no room anywhere near
## goes at the right edge, over the code, rather than not at all.
class Bubbles extends Control:
	const FS := 13
	const PAD := 10.0
	const GAP := 36.0              # (from the code to a bubble)
	const NEAR := 18               # (paragraphs up / down to look for room)
	var review: RichTextLabel
	var font: Font                 # (the code's: to measure it)
	var text_font: Font            # (the bubbles')
	var placed: Array = []         # [{rect (text coords), para, tip (text coords), text, cramped}]
	var _code: Dictionary = {}
	var _points: Array = []
	var _t := 0.0
	var _seen := 0                 # (bubbles come in one after another)
	var _width := -1.0

	func _ready() -> void:
		text_font = ThemeDB.fallback_font
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		review.get_v_scroll_bar().value_changed.connect(func(_v): queue_redraw())
		review.resized.connect(func():
			if not _points.is_empty() and absf(review.size.x - _width) > 1.0:
				_layout())
		set_process(false)

	func clear() -> void:
		_code = {}
		_points = []
		placed = []
		set_process(false)
		queue_redraw()

	func show_points(code: Dictionary, points: Array) -> void:
		_code = code
		_points = points
		placed = []
		_t = 0.0
		_seen = 0
		if points.is_empty():
			queue_redraw()
			return
		_layout.call_deferred()   # (once the text is laid out)

	func _margin() -> Vector2:
		var sb := review.get_theme_stylebox("normal")
		return Vector2(sb.get_margin(SIDE_LEFT), sb.get_margin(SIDE_TOP))

	## The paragraph's top and bottom (text coordinates).
	func _span(p: int) -> Vector2:
		var top := review.get_paragraph_offset(p)
		var bot: float = review.get_paragraph_offset(p + 1) if p + 1 < review.get_paragraph_count() else review.get_content_height()
		return Vector2(top, maxf(bot, top + 1.0))

	## How far right a paragraph's content reaches (inf: text across the width).
	func _reach(p: int, room: float) -> float:
		if not _code.has(p):
			return INF
		var w := font.get_string_size(_code[p], HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		return w if w < room else INF   # (a wrapped line fills the width)

	func _layout() -> void:
		placed = []
		_width = review.size.x
		if _points.is_empty() or review.get_paragraph_count() == 0:
			queue_redraw()
			return
		var m := _margin()
		# (the scroll bar only when it shows: hidden - a short file - it can
		# report the viewer's whole width, which left no room at all)
		var sb := review.get_v_scroll_bar()
		var sbw := sb.size.x if sb.visible else 0.0
		var right := review.size.x - m.x - sbw - 6.0   # (text coords)
		var room := review.size.x - 2.0 * m.x - sbw
		var count := review.get_paragraph_count()
		for pt in _points:
			var para: int = pt[0]
			if para >= count:
				continue
			var line := _span(para)
			var tip := Vector2(minf(_reach(para, room), right - 40.0) + 8.0, (line.x + line.y) / 2.0)
			var best := {}
			var best_score := INF
			for w in [380.0, 320.0, 260.0, 210.0]:
				w = minf(w, right - 60.0)
				if w < 150.0:
					break
				var h := text_font.get_multiline_string_size(pt[1], HORIZONTAL_ALIGNMENT_LEFT, w - 2.0 * PAD, FS).y + 2.0 * PAD
				for d in range(-NEAR, NEAR + 1):
					var top := _span(clampi(para + d, 0, count - 1)).x
					if para + d >= count:
						top = review.get_content_height() + (para + d - count) * 18.0
					elif para + d < 0:
						continue
					# Everything beside the bubble must end left of it.
					var reach := 0.0
					var q := clampi(para + d, 0, count - 1)
					while q < count and _span(q).x < top + h:
						reach = maxf(reach, _reach(q, room))
						q += 1
					var x := reach + GAP
					if x + w > right:
						continue
					var r := Rect2(x, top, w, h)
					if _hits(r):
						continue
					var score: float = absf(r.get_center().y - tip.y) + (x - tip.x) * 0.15 + (380.0 - w) * 0.3
					if score < best_score:
						best_score = score
						best = {"rect": r, "para": para, "tip": tip, "text": pt[1], "cramped": false}
			if best.is_empty():   # (no room near it: at the right edge, over the code)
				var w2 := maxf(150.0, minf(300.0, right - 20.0))
				var h2 := text_font.get_multiline_string_size(pt[1], HORIZONTAL_ALIGNMENT_LEFT, w2 - 2.0 * PAD, FS).y + 2.0 * PAD
				best = {"rect": Rect2(right - w2, tip.y + 14.0, w2, h2), "para": para, "tip": tip, "text": pt[1], "cramped": true}
			placed.append(best)
		queue_redraw()

	func _hits(r: Rect2) -> bool:
		for b in placed:
			if (b["rect"] as Rect2).grow(8.0).intersects(r):
				return true
		return false

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
		var busy := false
		for b in placed:
			busy = busy or (b.has("since") and _t - float(b["since"]) < 0.5)
		if not busy:
			set_process(false)

	func _draw() -> void:
		if placed.is_empty():
			return
		var off := _margin() - Vector2(0, review.get_v_scroll_bar().value)
		_seen = 0
		var gold := Color(1.0, 0.8, 0.35)
		for i in placed.size():
			var b: Dictionary = placed[i]
			var r: Rect2 = (b["rect"] as Rect2)
			r.position += off
			if r.end.y < 0.0 or r.position.y > size.y:
				continue
			if not b.has("since"):   # (each fades in when it first comes into view)
				b["since"] = _t + 0.15 * _seen
				_seen += 1
				set_process(true)
			var a := clampf((_t - float(b["since"])) / 0.35, 0.0, 1.0)
			if a <= 0.0:
				continue
			r.position.y += (1.0 - a) * 8.0
			var tip: Vector2 = b["tip"] + off
			# The line it's about, outlined.
			var line: Vector2 = _span(b["para"])
			draw_rect(Rect2(off.x - 4.0, line.x + off.y - 1.0, tip.x - off.x - 2.0, line.y - line.x + 1.0), Color(gold, 0.55 * a), false, 1.5)
			# The arrow: from the bubble's side, bowing, to the line's end.
			var from := Vector2(r.position.x, clampf(tip.y, r.position.y + 12.0, r.end.y - 12.0))
			if b["cramped"]:
				from = Vector2(clampf(tip.x + 30.0, r.position.x + 12.0, r.end.x - 12.0), r.position.y)
			var mid := (from + tip) / 2.0 + Vector2(0, -18.0 if from.y <= tip.y else 18.0) * clampf(absf(from.x - tip.x) / 200.0, 0.2, 1.0)
			var pts := PackedVector2Array()
			for k in 17:
				var u := k / 16.0
				pts.append(from.lerp(mid, u).lerp(mid.lerp(tip, u), u))
			draw_polyline(pts, Color(gold, a), 2.0, true)
			var dir := (tip - pts[14]).normalized()
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([tip, tip - dir * 10.0 + side * 5.0, tip - dir * 10.0 - side * 5.0]), Color(gold, a))
			# The bubble.
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.1, 0.13, 0.22, 0.96 * a)
			sb.border_color = Color(gold, a)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(10)
			sb.shadow_color = Color(0, 0, 0, 0.45 * a)
			sb.shadow_size = 6
			draw_style_box(sb, r)
			draw_multiline_string(text_font, r.position + Vector2(PAD, PAD + text_font.get_ascent(FS)), b["text"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 2.0 * PAD, FS, -1, Color(0.93, 0.95, 1.0, a))
