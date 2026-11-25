class_name DocPictures
## Screenshots of the game in the guide (F1), the tutorial and the
## encyclopedia: where their text has  ![caption](shot:id)  the picture
## (data/docs/shots/<id>.jpg - taken and annotated by tools/doc_shots.py,
## listed in data/docs/shots.json) shows, as wide as the text, its caption
## under it. A shot not taken yet shows as a dim line instead.

const DIR := "res://data/docs/shots/"
static var _re: RegEx


## `text` with every shot marker made a picture `width` px wide. `defer`: a
## picture not loaded yet isn't loaded now (a 1920 x 1080 picture read and
## decoded in the frame: a long one) - it's asked for in the background and a
## line stands in for it; loaded(text) says when to show the text again.
static func expand(text: String, width := 900.0, defer := false) -> String:
	if not text.contains("](shot:"):
		return text
	if _re == null:
		_re = RegEx.create_from_string("!\\[([^\\]]*)\\]\\(shot:([a-z0-9_]+)\\)")
	var out := ""
	var last := 0
	for m in _re.search_all(text):
		out += text.substr(last, m.get_start() - last)
		out += block(m.get_string(2), m.get_string(1), width, defer)
		last = m.get_end()
	return out + text.substr(last)


## The BBCode of one picture and its caption.
static func block(id: String, caption: String, width: float, defer := false) -> String:
	if caption.strip_edges() == "":
		caption = caption_of(id)
	var path := DIR + id + ".jpg"
	if not ResourceLoader.exists(path):
		return "[color=#6f6455][i](picture: %s - not taken yet)[/i][/color]" % caption
	if defer and not _ready_now(path):
		return "\n[center][color=#6f6455][i](loading the picture: %s)[/i][/color][/center]\n" % caption
	var w := int(clampf(width, 320.0, 1280.0))
	return "\n[center][img=%dx%d]%s[/img]\n[font_size=%d][color=#c9b48f][i]%s[/i][/color][/font_size][/center]\n" % [
		w, int(w * 9 / 16.0), path, Settings.fs("menu", 15), caption]


## A shot's caption from data/docs/shots.json (an empty marker's: ![](shot:id)).
static var _captions := {}

static func caption_of(id: String) -> String:
	if _captions.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/docs/shots.json"))
		if d is Dictionary:
			for k in d.get("shots", {}):
				_captions[k] = str(d["shots"][k].get("caption", ""))
	return str(_captions.get(id, ""))


## Pictures loaded in the background, kept (so the text's [img] finds them in the cache).
static var _held := {}

## Loaded (or asked for in the background now, and false until it's there).
static func _ready_now(path: String) -> bool:
	if _held.has(path) or ResourceLoader.has_cached(path):
		return true
	var st := ResourceLoader.load_threaded_get_status(path)
	if st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(path)
		return false
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		_held[path] = ResourceLoader.load_threaded_get(path)
		return true
	return false


## Every picture `text` shows is loaded (expand with `defer` shows them all now).
static func loaded(text: String) -> bool:
	for id in ids_in(text):
		var path := DIR + str(id) + ".jpg"
		if ResourceLoader.exists(path) and not _ready_now(path):
			return false
	return true


## The ids of the shots `text` shows.
static func ids_in(text: String) -> Array:
	if _re == null:
		_re = RegEx.create_from_string("!\\[([^\\]]*)\\]\\(shot:([a-z0-9_]+)\\)")
	return _re.search_all(text).map(func(m): return m.get_string(2))


## A width for pictures in a text box: its width less a margin (or `fallback`
## before it's laid out), at most 1000.
static func width_for(box: Control, fallback := 860.0) -> float:
	var w: float = box.size.x - 40.0 if box and box.size.x > 100.0 else fallback
	return minf(w, 1000.0)
