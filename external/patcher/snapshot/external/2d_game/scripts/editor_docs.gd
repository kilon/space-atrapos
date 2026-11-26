class_name EditorDocs
## The docs books (data/docs/*.md: the Talos manual, the pilot's guide, the
## tutorial), organised like books: chapters ("# id | Title", then an
## introduction) holding sections ("## id | Title"), written in a small
## Markdown subset - **bold**, `code`, "- " lists, [text](doc:id) links. Read
## here, shown in the Archive (EditorDocs.open() opens it at a section) and
## linked from every tooltip (PinTips). Chapter pages have the ids "ch:<chapter id>".

const FILE := "res://data/docs/editor.md"
## The player's guide (same format), for the game's own screens.
const GAME := "res://data/docs/game.md"
## The tutorial: lessons, in the order you need them.
const TUTORIAL := "res://data/docs/tutorial.md"
static var _file := FILE            # the book in use (see use())
static var _keywords: Array = []    # [keyword, section]: tooltip titles a section explains
static var _sections := {}          # id -> [title, markdown]
static var _order: Array = []
static var _chapters: Array = []    # [{id, title, intro, sections: [ids]}]
static var _chapter_of := {}        # section id -> chapter index

## Which section a tooltip's title points to: [keyword, section] (first match wins).
const TOPICS := [
	["Paint terrain", "level-tools"], ["Draw building", "level-tools"], ["Wall:", "level-tools"], ["Place ", "level-tools"],
	["Erase", "level-tools"],
	["Library", "zoo"], ["Save layout", "layouts"], ["Revert to generated", "layouts"],
	["Brush", "level-tools"], ["Kind", "level-tools"], ["Exit the level editor", "level-editor"],
	["Save to file", "data-editor"], ["Reload from file", "data-editor"], ["Back to the main menu", "data-editor"],
	["Dialogue", "dialogue"], ["Speaker", "dialogue"], ["Line", "dialogue"], ["Add line", "dialogue"], ["Quest stages", "dialogue"],
	["Quest", "quest"], ["Chapter", "quest"], ["Lore", "lore"], ["Interactions", "interactions"], ["citizen", "interactions"],
	["Minoan words", "interactions"], ["Translation", "interactions"], ["Sprites", "sprites"], ["sprites", "sprites"],
	["Characters", "zoo"], ["Ships", "zoo"], ["Stations", "zoo"], ["Planets", "zoo"], ["Buildings", "zoo"], ["Effects", "zoo"],
]


## Switches to another book (a docs file); each is read once and kept (the
## Archive reads several in turn).
static var _books := {}             # file -> [sections, order, chapters, chapter_of, keywords]
static func use(file: String) -> void:
	if file == _file:
		return
	if not _sections.is_empty():
		_books[_file] = [_sections, _order, _chapters, _chapter_of, _keywords]
	_file = file
	if _books.has(file):
		var b: Array = _books[file]
		_sections = b[0]
		_order = b[1]
		_chapters = b[2]
		_chapter_of = b[3]
		_keywords = b[4]
		return
	_sections = {}
	_order = []
	_chapters = []
	_chapter_of = {}
	_keywords = []


static func book() -> String:
	return _file


static func _load() -> void:
	if not _sections.is_empty():
		return
	var text := FileAccess.get_file_as_string(_file)
	var id := ""
	var body := PackedStringArray()
	for line in text.split("\n"):
		if line.begins_with("# ") and line.contains("|"):   # a chapter
			_flush(id, body)
			var head := line.substr(2).split("|", true, 1)
			id = "ch:" + head[0].strip_edges()
			_chapters.append({"id": id, "title": head[1].strip_edges(), "intro": "", "sections": []})
			body = PackedStringArray()
		elif line.begins_with("## "):
			_flush(id, body)
			# "## id | Title | keywords: a, b" - the keywords are tooltip titles it explains.
			var head := line.substr(3).split("|")
			id = head[0].strip_edges()
			_sections[id] = [head[1].strip_edges() if head.size() > 1 else id, ""]
			if head.size() > 2 and head[2].strip_edges().begins_with("keywords:"):
				for kw in head[2].strip_edges().substr(9).split(","):
					if kw.strip_edges() != "":
						_keywords.append([kw.strip_edges(), id])
			_order.append(id)
			if not _chapters.is_empty():
				_chapters[-1]["sections"].append(id)
				_chapter_of[id] = _chapters.size() - 1
			body = PackedStringArray()
		elif id != "":
			body.append(line)
	_flush(id, body)


static func ids() -> Array:
	_load()
	return _order


## Stores the text read for a chapter introduction or a section.
static func _flush(id: String, body: PackedStringArray) -> void:
	if id.begins_with("ch:"):
		_chapters[-1]["intro"] = "\n".join(body).strip_edges()
	elif id != "":
		_sections[id][1] = "\n".join(body).strip_edges()


static func chapters() -> Array:
	_load()
	return _chapters


static func _chapter(id: String) -> Dictionary:
	for c in _chapters:
		if c["id"] == id:
			return c
	return {}


static func title(id: String) -> String:
	_load()
	if id.begins_with("ch:"):
		return _chapter(id).get("title", id)
	return _sections[id][0] if _sections.has(id) else id


## "2.3" for a section, "2" for a chapter ("" if not in a chapter).
static func number(id: String) -> String:
	_load()
	for i in _chapters.size():
		if _chapters[i]["id"] == id:
			return str(i + 1)
	if _chapter_of.has(id):
		var ci: int = _chapter_of[id]
		return "%d.%d" % [ci + 1, _chapters[ci]["sections"].find(id) + 1]
	return ""


## "2.3  Title".
static func numbered(id: String) -> String:
	var n := number(id)
	return (n + "  " if n != "" else "") + title(id)


static func has(id: String) -> bool:
	_load()
	return _sections.has(id) or not _chapter(id).is_empty()


## The chapter a section belongs to ("" if none).
static func chapter_of(id: String) -> String:
	_load()
	return _chapters[_chapter_of[id]]["id"] if _chapter_of.has(id) else ""


## Reading order: every chapter page, then its sections.
static func reading_order() -> Array:
	_load()
	var out := []
	for c in _chapters:
		out.append(c["id"])
		out.append_array(c["sections"])
	return out


## The section a tooltip (by its title) is about ("" if none matches).
static func topic(tip_title: String) -> String:
	_load()
	for t in _keywords:
		if tip_title.contains(t[0]):
			return t[1]
	if _file != FILE:
		return ""
	for t in TOPICS:
		if tip_title.contains(t[0]):
			return t[1]
	return ""


## Markdown subset -> BBCode.
static func to_bbcode(md: String) -> String:
	var out := PackedStringArray()
	var re_b := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	var re_c := RegEx.create_from_string("`([^`]+)`")
	var re_l := RegEx.create_from_string("\\[([^\\]]+)\\]\\((doc:[a-z0-9-]+)\\)")
	for line in md.split("\n"):
		# Code spans first, their brackets shown literally.
		var l := ""
		var last := 0
		for m in re_c.search_all(line):
			l += line.substr(last, m.get_start() - last)
			l += "[color=#ffd27a][code]" + m.get_string(1).replace("[", "[lb]") + "[/code][/color]"
			last = m.get_end()
		l += line.substr(last)
		l = re_b.sub(l, "[b]$1[/b]", true)
		l = re_l.sub(l, "[color=#7fd6ff][url=$2]$1[/url][/color]", true)
		if l.begins_with("- "):
			l = "  •  " + l.substr(2)
		out.append(l)
	return "\n".join(out)


static func body(id: String) -> String:
	_load()
	if id.begins_with("ch:"):
		var c := _chapter(id)
		var lines := [to_bbcode(c.get("intro", "")), "", "[b]In this chapter:[/b]"]
		for s in c.get("sections", []):
			lines.append("  %s   [color=#7fd6ff][url=doc:%s]%s[/url][/color]" % [number(s), s, title(s)])
		return "\n".join(lines)
	return to_bbcode(_sections[id][1]) if _sections.has(id) else ""


## Searchable text of a page.
static func text_of(id: String) -> String:
	_load()
	if id.begins_with("ch:"):
		var c := _chapter(id)
		return c.get("title", "") + " " + c.get("intro", "")
	return title(id) + " " + (_sections[id][1] if _sections.has(id) else "")


## Opens the Archive (the one window for all the game's books) at a section
## of book `file` (FILE, the editor's; GAME, the player's guide; TUTORIAL).
static func open(owner: Node, id := "", file := "") -> void:
	if file == "":
		file = _file
	var b: String = {FILE: "talos", GAME: "guide", TUTORIAL: "tutorial"}.get(file, "guide")
	if id == "":
		id = "overview" if file == FILE else "start"
	use(file)
	# (loaded now, not named: this class is used before the autoloads exist - by -s scripts too)
	load("res://scripts/archive.gd").open(owner, b, b + "/" + id if has(id) else "")
