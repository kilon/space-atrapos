extends TestCase
## The Archive (Archive): every book of the game in one browser - the guide,
## the tutorial, the encyclopedia, the controls, the versions and the Talos
## manual. Every page of every book shows, every link leads somewhere, one
## search finds pages in all the books, Back / Forward retrace your steps,
## and F1, the Guide buttons and the computers all open it.

var _main: Node


func teardown() -> void:
	for w in tree.get_nodes_in_group("archive_window"):
		w.get_parent().free()
	if is_instance_valid(_main):
		_main.queue_free()


func _window() -> Archive:
	var a := Archive.open(tree.root, "guide")
	return a


func test_every_book_and_page() -> void:
	var a := _window()
	await tree.process_frame
	check_eq(Archive.BOOKS.map(func(b): return b["id"]), ["guide", "tutorial", "encyclopedia", "controls", "versions", "talos"], "the shelf")
	for b in Archive.BOOKS:
		var toc := a.contents(b["id"])
		var n := 0
		for ch in toc:
			for p in ([[ch["id"], ""]] if ch["id"] != "" else []) + ch["pages"]:
				n += 1
				var pg := a.page(p[0])
				check(not pg.is_empty() and str(pg["body"]).length() > 20, "%s: %s has text" % [b["title"], p[0]])
				# Every link goes to a page that's there.
				for m in RegEx.create_from_string("doc:([a-z0-9:/._-]+)").search_all(str(pg.get("body", ""))):
					var to := a.resolve(m.get_string(1))
					check(a.has_page(to), "%s links to %s (%s)" % [p[0], m.get_string(1), to])
		check(n > 0 or b["id"] == "encyclopedia", "%s has pages (%d)" % [b["title"], n])
	check(a.contents("tutorial").size() >= 1 and a.contents("tutorial")[0]["pages"].size() >= 19, "the tutorial's lessons")
	check(a.page("tutorial/t-repairs").get("title", "").contains("Repairs"), "a lesson on repairs")
	check(a.page("guide/repair-bay")["body"].contains("Welder"), "the guide's Repair Bay section")
	check(a.contents("versions").size() >= 3, "the versions, each with its patches")
	check(a.page("controls/flight")["body"].contains("Tab"), "the controls as bound (the computer on Tab)")


func test_search_reaches_every_book() -> void:
	var a := _window()
	await tree.process_frame
	a._search.text = "weld"
	a._fill_toc()
	var books := []
	var it := a._toc.get_root().get_first_child()
	while it:
		books.append(it.get_text(0))
		it = it.get_next()
	check(books.has("Pilot's Guide") and books.has("Tutorial"), "one search, several books (%s)" % str(books))
	a._search.text = "zzqx nothing"
	a._fill_toc()
	check(a._toc.get_root().get_first_child().get_text(0).begins_with("Nothing"), "no match: says so")
	a._search.text = ""
	a._fill_toc()


func test_links_history_and_entry_points() -> void:
	var a := _window()
	await tree.process_frame
	a.show_page("guide/repair")
	a._on_link("doc:repair-bay")
	check_eq(a._current, "guide/repair-bay", "a link opens its page")
	a._on_link("doc:t-repairs")
	check_eq(a._current, "tutorial/t-repairs", "a link to another book's page finds it")
	a.go_back()
	check_eq(a._current, "guide/repair-bay", "Back")
	a.go_back()
	check_eq(a._current, "guide/repair", "Back again")
	a.go_forward()
	check_eq(a._current, "guide/repair-bay", "Forward")
	check(a._shelf["guide"].button_pressed and not a._shelf["tutorial"].button_pressed, "the shelf shows the open book")
	# F1 / the Guide buttons (EditorDocs.open): the same window, at their page.
	EditorDocs.open(tree.root, "level-tools", EditorDocs.FILE)
	check_eq(tree.get_nodes_in_group("archive_window").size(), 1, "one Archive window")
	check_eq(a._current, "talos/level-tools", "the Talos manual's page")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	tree.get_nodes_in_group("archive_window")[0]._input(esc)
	await tree.process_frame
	check(tree.get_nodes_in_group("archive_window").is_empty(), "Esc closes it")


func test_in_the_ship_computer() -> void:
	Galaxy.new_game(false)
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 10:
		await tree.process_frame
	_main.ship_menu.open(_main.ship_menu.ARCHIVE_TAB)
	await tree.process_frame
	var a: Archive = _main.ship_menu._pages[_main.ship_menu.ARCHIVE_TAB]
	check(a.visible and a._current != "", "the Ship Computer's Archive tab opens on a page (%s)" % a._current)
	a.open_book("encyclopedia")
	check(a._current.begins_with("encyclopedia/") and a._pic_box.visible, "the encyclopedia: an entry with its picture")
	a.open_book("controls")
	check(a._current.begins_with("controls/"), "the controls")
	_main.ship_menu.close()
