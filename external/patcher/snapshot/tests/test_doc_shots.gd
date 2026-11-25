extends TestCase
## The screenshots in the guide, the tutorial and the encyclopedia
## (data/docs/shots.json, tools/doc_shots.py): every one shown exists, every
## one listed is shown somewhere, and none is older than the files it shows -
## when one is, take it again:  python3 tools/doc_shots.py --stale

const PAGES := ["res://data/docs/game.md", "res://data/docs/tutorial.md", "res://scripts/ui/encyclopedia.gd"]


func _shots() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/docs/shots.json"))["shots"]


func test_every_shot_shown_exists_and_every_one_is_shown() -> void:
	var shots := _shots()
	var shown := {}
	for p in PAGES:
		for id in DocPictures.ids_in(FileAccess.get_file_as_string(p)):
			shown[id] = true
			check(shots.has(id), "%s shows shot '%s': it's in shots.json" % [p.get_file(), id])
			check(ResourceLoader.exists(DocPictures.DIR + id + ".jpg"), "%s: its picture is there (python3 tools/doc_shots.py %s)" % [id, id])
	for id in shots:
		check(shown.has(id), "shot '%s' is shown somewhere (a page's text has ![](shot:%s))" % [id, id])
		check(str(shots[id].get("caption", "")).length() > 10, "%s has a caption" % id)


## (The same fingerprint tools/doc_shots.py keeps: each source's path and contents.)
func _hash(sources: Array) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	for s in sources:
		h.update(str(s).to_utf8_buffer())
		var p := "res://" + str(s)
		h.update(FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else "-".to_utf8_buffer())
	return h.finish().hex_encode()


func test_every_shot_is_up_to_date() -> void:
	var shots := _shots()
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/docs/shots/manifest.json"))
	check(m is Dictionary, "the shots' manifest is there")
	if not m is Dictionary:
		return
	for id in shots:
		var rec: Dictionary = m.get(id, {})
		check(rec.get("hash", "") == _hash(shots[id]["sources"]),
			"shot '%s' is older than what it shows (%s) - take it again: python3 tools/doc_shots.py --stale" % [id, ", ".join(shots[id]["sources"])])


func test_a_shot_becomes_a_picture() -> void:
	var t := DocPictures.expand("Before.\n![](shot:space3d)\nAfter.", 800.0)
	check(t.contains("[img=800x450]res://data/docs/shots/space3d.jpg[/img]"), "a marker: the picture, as wide as asked")
	check(t.contains(DocPictures.caption_of("space3d")), "and its caption (from shots.json)")
	check(t.begins_with("Before.") and t.ends_with("After."), "the text round it kept")
	check(DocPictures.expand("![Gone](shot:no_such_shot)").contains("not taken yet"), "a shot not taken: a line saying so")
	var bb := EditorDocs.to_bbcode("Fly.\n![](shot:space3d)")
	check(DocPictures.expand(bb).contains("[img="), "the guide's markdown keeps the marker for it")
