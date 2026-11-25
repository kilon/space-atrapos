extends TestCase
## The editor (main menu > Editor) and the asset zoo.


func test_editor_on_main_menu_not_in_game() -> void:
	var menu: Control = load("res://main_menu.tscn").instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	var b := menu.find_child("EditorButton", true, false)
	check(b != null and b.visible, "the title screen has the editor's button")
	check(b != null and b.text.to_lower() == "talos", "the editor is called Talos (%s)" % (b.text if b else ""))
	menu.queue_free()
	await tree.process_frame
	# Developer Mode is gone from the in-game right-click menus.
	for f in ["res://scripts/main.gd", "res://scripts/planet_surface.gd"]:
		var src := FileAccess.get_file_as_string(f)
		check(not src.contains("Developer Mode") and not src.contains("DevMode"), f.get_file() + ": no Developer Mode")


func test_editor_pages() -> void:
	var ed: Control = load("res://editor.tscn").instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	var dm: DevMode = null
	for c in ed.get_children():
		if c is DevMode:
			dm = c
	check(dm != null and dm.visible, "the editor shows the data editor")
	if dm:
		for i in DevMode.TABS.size():
			dm.show_tab(i)
			await tree.process_frame
			check(dm._content.get_child_count() > 0, "tab %s has content" % DevMode.TABS[i])
	check(not tree.paused, "the editor doesn't pause the tree")
	ed.queue_free()
	await tree.process_frame


## Planets, suns and nebulae in the zoo: selectable, with a property panel of
## at least 12 properties for every kind and mode, edited live.
## Procedural asteroids: varied, and the game's rocks are built from them.
func test_asteroid_generator() -> void:
	var seen := {}
	for v in 40:
		var p := AsteroidGen.generate(AsteroidGen.TEMPLATES.keys()[v % 2], v + 1)
		var key := "%.3f|%.3f|%.3f|%s" % [p["elongation"], p["binary"], p["seed"], p["c_rock"]]
		seen[key] = true
	check(seen.size() == 40, "40 variants are all different (%d)" % seen.size())
	check(AsteroidGen.PROPERTIES.filter(func(d): return d[0] != "#").size() >= 12, "at least 12 editable properties")
	var ti := AsteroidGen.for_rock("titanium", 5, false)
	check(float(ti["veins"]) > 0.5 and float(ti["vein_glow"]) > 0.5, "titanium rocks have glowing veins")
	var fx := Node2D.new()   # (ore pickups go to the fx layer)
	fx.add_to_group("fx_layer")
	tree.root.add_child(fx)
	var rock := Asteroid.new().setup(Asteroid.random_data(Vector2.ZERO))
	tree.root.add_child(rock)
	await tree.process_frame
	var mat: ShaderMaterial = rock._sprite.material
	check(mat.shader == AsteroidGen.SHADER, "the game's asteroid uses the procedural shader")
	rock.targeted = true
	check(float(mat.get_shader_parameter("outline")) == 1.0, "locking on lights the shader outline")
	var before := rock.scale.x
	rock.take_damage(Asteroid.DAMAGE_PER_ORE * 2.0, rock.global_position)
	check(rock.ore_total >= Asteroid.ORE_SCALE, "rocks hold %dx the ore (%d)" % [Asteroid.ORE_SCALE, rock.ore_total])
	var left: int = rock.ore_left
	rock.mine(Asteroid.DAMAGE_PER_ORE * 3.0, rock.global_position, null)
	check(rock.ore_left == left - 3, "the mining beam cuts ore off")
	rock.ore_left = maxi(1, rock.ore_total / 50)   # nearly mined out: it has shrunk
	rock._update_size()
	check(rock.scale.x < before, "mining shrinks it")
	rock.queue_free()
	fx.queue_free()
	await tree.process_frame


func test_zoo_property_panel() -> void:
	var zoo: Node2D = load("res://zoo.tscn").instantiate()
	tree.root.add_child(zoo)
	await tree.process_frame
	for r in [["PLANETS", "planet", 2], ["ASTEROIDS", "asteroid", 1], ["SUNS", "star", 1], ["NEBULAE", "nebula", 4]]:
		zoo.show_room(zoo.ROOMS.find(r[0]))
		for i in 5:
			await tree.process_frame
		check(not zoo._pickables.is_empty(), "%s has selectable exhibits" % r[0])
		var e: Dictionary = zoo._pickables[0]
		zoo.pick((e["holder"] as Node2D).position + Vector2(10, 5))
		await tree.process_frame
		check(zoo._sel == e and zoo._panel.visible, "%s: clicking an exhibit selects it" % r[0])
		for m in r[2]:
			if r[2] > 1:
				zoo._on_prop_changed("mode", m)
				await tree.process_frame
				await tree.process_frame
			check(zoo._panel.row_count() >= 12, "%s mode %d: %d properties (>= 12)" % [r[0], m, zoo._panel.row_count()])
		zoo._panel.changed.emit("seed", 33.0)
		var node: Node = zoo._sel["node"]
		var mat: ShaderMaterial = node.get_meta("planet_mat") if r[1] == "planet" else node.material
		check(is_equal_approx(float(mat.get_shader_parameter("seed")), 33.0), "%s: edits reach the shader" % r[0])
		zoo._panel.variant_changed.emit(5)
		check(int(zoo._sel["spec"]["variant"]) == 5, "%s: the variant regenerates it" % r[0])
		# The wheel over the panel (e.g. at the end of its list) must not zoom the view.
		var z0: float = zoo._zoom
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = zoo._panel.get_global_rect().get_center()
		zoo._unhandled_input(wheel)
		check(is_equal_approx(zoo._zoom, z0), "%s: scrolling over the panel doesn't zoom the view" % r[0])
		wheel.position = Vector2(400, 500)   # (in the view - past the rail)
		zoo._unhandled_input(wheel)
		check(not is_equal_approx(zoo._zoom, z0), "%s: scrolling over the view still zooms it" % r[0])
		zoo.pick(Vector2(99999, 99999))
		check(zoo._sel.is_empty() and not zoo._panel.visible, "%s: clicking empty space deselects" % r[0])
	zoo.queue_free()
	await tree.process_frame


## Characters and buildings are themeable too; looks save as named presets
## whose rules decide where the game uses them.
func test_library_themes_and_presets() -> void:
	var zoo: Node2D = load("res://zoo.tscn").instantiate()
	tree.root.add_child(zoo)
	await tree.process_frame
	# Buildings: a style is one exhibit; recolouring reaches its materials.
	zoo.show_room(zoo.ROOMS.find("BUILDINGS"))
	for i in 5:
		await tree.process_frame
	var bl: Array = zoo._pickables.filter(func(x): return x["kind"] == "building")
	check(bl.size() == MinoanTiles.STYLES.size(), "every building style is selectable")
	zoo.pick((bl[0]["rect"] as Rect2).get_center())
	check(zoo._sel == bl[0], "clicking a style selects it")
	zoo._panel.changed.emit("plaster_amount", 1.0)
	var wm: ShaderMaterial = BuildingLook.material(bl[0]["node"], "walls")
	check(wm != null and float(wm.get_shader_parameter("cloth_amount")) == 1.0, "the walls' material takes the edit")
	check((bl[0]["items"]["walls"][0] as CanvasItem).material == wm, "the walls wear it")
	# Presets: save, list, load, delete.
	var name := "__test_preset__"
	zoo._save_preset(name, {"systems": ["klotho"], "chapter_min": 2})
	check(not Themes.find("building", name).is_empty(), "a preset saves")
	var r := Themes.rules_of(Themes.find("building", name))
	check(Themes.matches(r, {"system": "klotho", "chapter": 3}) and not Themes.matches(r, {"system": "atrapos", "chapter": 3})
		and not Themes.matches(r, {"system": "klotho", "chapter": 1}), "its rules filter by system and chapter")
	zoo._load_preset(name)
	check(zoo._sel.get("preset") == name, "a preset loads")
	Themes.delete_preset("building", name)
	check(Themes.find("building", name).is_empty(), "a preset deletes")
	# Rules with templates.
	check(Themes.matches({"templates": ["ocean"]}, {}, "ocean") and not Themes.matches({"templates": ["ocean"]}, {}, "inferno"),
		"template rules")
	# The GUI room: edits restyle the interface; leaving restores it.
	var before := NeonTheme.CYAN
	zoo.show_room(zoo.ROOMS.find("GUI"))
	for i in 3:
		await tree.process_frame
	check(zoo._sel.get("kind") == "gui", "the GUI room opens its look in the panel")
	zoo._panel.changed.emit("main_color", Color(1.0, 0.5, 0.0))
	check(NeonTheme.CYAN.is_equal_approx(Color(1.0, 0.5, 0.0)), "a GUI edit restyles the interface")
	zoo.queue_free()
	await tree.process_frame
	await tree.process_frame
	check(NeonTheme.CYAN.is_equal_approx(before), "leaving the Library restores the GUI look")


func test_zoo_rooms() -> void:
	var zoo: Node2D = load("res://zoo.tscn").instantiate()
	tree.root.add_child(zoo)
	await tree.process_frame
	for r in zoo.ROOMS.size():
		zoo.show_room(r)
		for i in 20:
			await tree.process_frame
		check(zoo.world.get_child_count() > 0, "room %s has exhibits" % zoo.ROOMS[r])
		var hits: Array = zoo.plate_overlaps()
		check(hits.is_empty(), "room %s: no plate's text over another's (%s)" % [zoo.ROOMS[r],
			", ".join(hits.slice(0, 3).map(func(h): return "%s / %s" % [h[0].text.left(20), h[1].text.left(20)]))])
	zoo.show_room(0)
	await tree.process_frame
	var rigs := {}
	var citizens := {}
	for n in zoo.world.get_children():
		if "rig" in n and n.get_child_count() > 0 and n.get_child(0) is SheetPuppet:
			var sp: SheetPuppet = n.get_child(0)
			rigs["%s %s %s" % [n.rig, sp._view, sp._pose]] = true
		if n is SurfaceProps.MinoanNpc:
			citizens[n.species] = true
	check(rigs.size() >= 16, "the guard in all its views, idle and aiming (%d)" % rigs.size())
	for k in SurfaceProps.CITIZENS:
		check(citizens.has(k), "the %s at work" % k)
	zoo.queue_free()
	await tree.process_frame


func test_docs_and_pinned_tooltips() -> void:
	check(EditorDocs.ids().size() >= 20, "the documentation has its sections")
	check_eq(EditorDocs.chapters().size(), 8, "eight chapters")
	for c in EditorDocs.chapters():
		check(not c["sections"].is_empty() and c["intro"] != "", "chapter %s has an introduction and sections" % c["title"])
	check_eq(EditorDocs.number("level-tools"), "5.2", "sections are numbered by chapter")
	check_eq(EditorDocs.reading_order().size(), EditorDocs.ids().size() + EditorDocs.chapters().size(), "every section is in a chapter")
	for id in EditorDocs.ids():
		check(EditorDocs.body(id).length() > 40, "section '%s' has text" % id)
		# Every link points to an existing section.
		for m in RegEx.create_from_string("doc:([a-z0-9-]+)").search_all(EditorDocs._sections[id][1]):
			check(EditorDocs.has(m.get_string(1)), "%s links to %s" % [id, m.get_string(1)])
	# The pilot's guide (game screens): its own chapters, every link valid.
	EditorDocs.use(EditorDocs.GAME)
	check(EditorDocs.chapters().size() >= 5, "the pilot's guide has chapters")
	for id in EditorDocs.ids():
		for m in RegEx.create_from_string("doc:([a-z0-9-]+)").search_all(EditorDocs._sections[id][1]):
			check(EditorDocs.has(m.get_string(1)), "guide: %s links to %s" % [id, m.get_string(1)])
	check_eq(EditorDocs.topic("Buy 10 Iron Ore"), "market", "guide topics come from the section keywords")
	EditorDocs.use(EditorDocs.FILE)
	var parsed := PinTips.parse(EditorIcons.tip("Rotate tool", "E", "Turns the part."))
	check_eq(parsed, ["Rotate tool", "E", "Turns the part."], "tooltips parse into title, keys and text")
	check_eq(EditorDocs.topic("Paint terrain"), "level-tools", "tooltips link to their topic")
	# Every icon button on the editor screens: its icon, a short label (two words at most) and a full tooltip.
	for scene in ["res://editor.tscn", "res://zoo.tscn"]:
		var n: Node = load(scene).instantiate()
		tree.root.add_child(n)
		for i in 5:
			await tree.process_frame
		for b in n.find_children("*", "Button", true, false):
			if b is OptionButton or b is CheckBox or b.get_parent() is HBoxContainer and b.toggle_mode and b.button_group != null and b.text != "" and b.icon != null:
				continue   # (lists, checkboxes and tabs keep their labels)
			if b.has_meta("talos_nav"):
				check(b.icon != null and b.text != "" and str(b.tooltip_text).length() > 60, "%s: the rail's '%s' has an icon, its name and a tooltip" % [scene.get_file(), b.text])
				continue   # (Talos's rail names every tool under its icon)
			if not b.is_visible_in_tree() or b.get_parent() is PopupMenu:
				continue
			var tip: String = b.tooltip_text if b.tooltip_text != "" else str(b.get_meta("tip", ""))
			if b.icon != null and b.text != "✕":
				check(b.text != "" and b.text.split(" ", false).size() <= 2, "%s: a short label beside the icon ('%s')" % [scene.get_file(), b.text])
			check(tip.length() > 60 or b.text == "✕", "%s: a full tooltip on '%s'" % [scene.get_file(), PinTips.parse(tip)[0] if tip != "" else b.name])
		n.queue_free()
		await tree.process_frame


## The SVG Editor: drawing with the tools, editing, undo, save / open, PNG export.
## The Patcher (Talos > Patcher): patches with a summary and a step-by-step
## infographic whose diagram elements are all drawable.
## Every patch and version diagram reads easily: its text at least
## PatchView.MIN_TEXT (14 px on the Versions page at 1920 x 1080), each
## label inside its box, on the canvas, no two texts over each other.
func test_patch_diagrams_readable() -> void:
	var view = load("res://scripts/patcher.gd").PatchView
	var n := 0
	for f in DirAccess.get_files_at("res://data/patches"):
		if not f.ends_with(".json"):
			continue
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/patches/" + f))
		var steps: Array = d.get("steps", [])
		for i in steps.size():
			var dg = steps[i].get("diagram", [])
			if dg is Array and not dg.is_empty():
				n += 1
				var probs: Array = view.lint(dg, ThemeDB.fallback_font)
				check(probs.is_empty(), "%s, page %d: %s" % [f, i + 1, probs.slice(0, 4)])
	check(n >= 100, "every diagram checked (%d)" % n)
	check(view.MIN_TEXT * 0.86 >= Settings.MIN_FONT, "the smallest diagram text is at least %d px on the Versions page" % Settings.MIN_FONT)


func test_patcher() -> void:
	var ed: Control = load("res://editor.tscn").instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	var dm: Node = ed.find_children("*", "DevMode", true, false)[0] if not ed.find_children("*", "DevMode", true, false).is_empty() else ed.get_child(0)
	check(dm.has_signal("patcher_requested"), "Talos opens the Patcher")
	ed.queue_free()
	await tree.process_frame
	var p: Control = load("res://patcher.tscn").instantiate()
	tree.root.add_child(p)
	await tree.process_frame
	for i in 300:   # (the unpublished changes are scanned on a worker thread)
		if not p.scanning:
			break
		await tree.process_frame
	check(not p.patches.is_empty(), "there are patches (%d)" % p.patches.size())
	var kinds := ["box", "text", "arrow", "circle", "grid", "iso", "bar", "badge", "poly"]
	# Unpublished changes (tracked in external/patcher/) come first, when there are any.
	if not p.patches.is_empty() and p.patches[0].get("pending", false):
		var un: Dictionary = p.patches[0]
		check(un["review"]["intro"].contains("# Pending changes"), "unpublished changes show the change log")
		p.show_patch(0)
		await tree.process_frame
		check(p._review_box.visible and p._tabs.is_tab_disabled(0), "unpublished changes open on the review (no infographic yet)")
		check(p._review.get_parsed_text().contains("Pending changes") and p._files.item_count > 0, "with the log and the changed files")
	var published: Array = p.patches.filter(func(x): return not x.get("pending", false) and x.get("kind", "") != "version")
	check(not published.is_empty(), "there are published patches")
	# Versions: each with its own summary and a page per patch, its patches under it in the tree.
	var versions: Array = []
	for i in p.patches.size():
		if p.is_version(i):
			versions.append(i)
	check(not versions.is_empty(), "there's a version")
	for vi in versions:
		var v: Dictionary = p.patches[vi]
		check(str(v.get("summary", "")).length() > 100 and not str(v["summary"]).contains("\n"), "version %s: a one-paragraph summary" % v["id"])
		check_eq(v["steps"].size(), v["patches"].size(), "version %s: a page for each patch" % v["id"])
		for st in v["steps"]:
			check(str(st.get("patch", "")) in v["patches"] and not st.get("diagram", []).is_empty(), "version %s: every page is about one of its patches, with a diagram" % v["id"])
			for e in st.get("diagram", []):
				check(e.get("t") in kinds, "version %s: a known diagram element (%s)" % [v["id"], e.get("t")])
		var kids: Array = []
		for k in p.patches.size():
			if p._parent[k] == vi:
				kids.append(str(p.patches[k]["id"]))
		var want: Array = v["patches"].duplicate()
		kids.sort()
		want.sort()
		check_eq(kids, want, "version %s: its patches are under it in the tree" % v["id"])
		check(p._items[vi].get_child_count() == want.size(), "version %s: shown as a tree" % v["id"])
		p.show_patch(vi)
		await tree.process_frame
		check(p._tabs.is_tab_disabled(1) and p._info_box.visible, "a version: the infographic, no code review")
		check(p._counter.text.begins_with("Page 1 / ") and p._counter.text.contains("patch "), "pages, each naming its patch (%s)" % p._counter.text)
		p.open_page_patch()
		check(str(p.patches[p.current].get("id", "")) == str(v["steps"][0]["patch"]) and p._parent[p.current] == vi, "a page opens its patch")
	for patch in published:
		check(str(patch.get("summary", "")).length() > 100, "%s: a one-paragraph summary" % patch["id"])
		check(not str(patch.get("summary", "")).contains("\n"), "%s: the summary is one paragraph" % patch["id"])
		check(patch["steps"].size() >= 3, "%s: several steps" % patch["id"])
		for st in patch["steps"]:
			check(str(st.get("title", "")) != "" and str(st.get("text", "")) != "", "%s: every step has a title and a caption" % patch["id"])
			check(not st.get("diagram", []).is_empty(), "%s / %s: a diagram" % [patch["id"], st["title"]])
			for e in st.get("diagram", []):
				check(e.get("t") in kinds, "%s: a known diagram element (%s)" % [patch["id"], e.get("t")])
		# The code review: every changed file, hunk by hunk, each explained.
		var rv: Dictionary = patch.get("review", {})
		check(not rv.get("files", []).is_empty(), "%s: a code review" % patch["id"])
		for fl in rv.get("files", []):
			check(str(fl.get("explanation", "")) != "", "%s: %s is explained" % [patch["id"], fl["path"]])
			for h in fl["hunks"]:
				check(str(h.get("title", "")) != "" and str(h.get("note", "")) != "", "%s: every hunk of %s has a title and a note" % [patch["id"], fl["path"]])
				var lines: PackedStringArray = str(h["diff"]).split("\n")
				check(lines[0].begins_with("@@"), "%s: %s hunks are unified diffs" % [patch["id"], fl["path"]])
				var adds := 0
				var rems := 0
				for l in lines.slice(1):
					adds += 1 if l.begins_with("+") else 0
					rems += 1 if l.begins_with("-") else 0
				check(adds == int(h["added"]) and rems == int(h["removed"]), "%s: %s line counts match the diff" % [patch["id"], fl["path"]])
				for bu in h.get("bubbles", []):
					check(str(bu.get("text", "")) != "" and p.bubble_line(lines, bu) > 0, "%s: %s - a bubble points at a line of its hunk (%s)" % [patch["id"], fl["path"], bu.get("at", "")])
	var first: int = p.patches.find(published[0])
	p.show_patch(first)
	p._tabs.current_tab = 1
	await tree.process_frame
	check(p._review_box.visible and not p._info_box.visible, "the Code review tab")
	check(p._rows.filter(func(r): return r >= 0).size() == published[0]["review"]["files"].size(), "lists the changed files")
	var rv_files: Array = published[0]["review"]["files"]
	var groups: Array = []
	for r in p._rows:
		if r >= 0:
			groups.append(p._file_group(rv_files[r]["path"]))
	var sorted_groups := groups.duplicate()
	sorted_groups.sort()
	check(groups == sorted_groups, "code files are listed first, then other text, then assets")
	check(p._file_group("scripts/a.gd") == 0 and p._file_group("tools/b.py") == 0 and p._file_group("data/c.json") == 1 and p._file_group("art/d.png") == 2, "file groups")
	# Explanation bubbles: beside the code, pointing at their lines, not over each other.
	var bf := -1
	var nb := 0
	for k in rv_files.size():
		var c := 0
		for h in rv_files[k]["hunks"]:
			c += h.get("bubbles", []).size()
		if c > 0 and bf < 0:
			bf = k
			nb = c
	if bf >= 0:
		p.show_file(p._rows.find(bf))
		for i in 3:
			await tree.process_frame
		check_eq(p._bubbles.placed.size(), nb, "every bubble of the file is placed")
		var apart := true
		var beside := true
		for i in p._bubbles.placed.size():
			var r: Rect2 = p._bubbles.placed[i]["rect"]
			if not p._bubbles.placed[i]["cramped"]:   # (nothing written under it)
				for q in p._review.get_paragraph_count():
					var sp: Vector2 = p._bubbles._span(q)
					if sp.y > r.position.y + 1.0 and sp.x < r.end.y - 1.0:
						beside = beside and p._bubbles._reach(q, 1e9) < r.position.x
			for j in range(i + 1, p._bubbles.placed.size()):
				apart = apart and not r.intersects(p._bubbles.placed[j]["rect"])
		check(apart, "bubbles don't cover each other")
		check(beside, "bubbles sit in empty space, beside the code")
	p.show_file(p._rows.find(1))
	check(p._review.get_parsed_text().contains(published[0]["review"]["files"][1]["path"]), "shows the chosen file's review")
	# Assets are shown as what they are: pictures (also all together), sounds, fonts.
	var img := -1
	for k in rv_files.size():
		if rv_files[k]["path"].ends_with(".png") and FileAccess.file_exists("res://" + rv_files[k]["path"]):
			img = k
	if img >= 0:
		check(p._rows.has(-1), "an 'All assets' gallery when a change has assets")
		check(p._image_texture(rv_files[img]["path"]) != null, "a changed picture can be read (%s)" % rv_files[img]["path"])
		p.show_file(p._rows.find(img))
		check(p._review.get_parsed_text().contains(" px"), "a picture is shown with its size")
		p.show_file(p._rows.find(-1))
		check(p._review.get_parsed_text().contains("All assets"), "the gallery")
	check(p._asset_kind("a/b.ogg") == "sound" and p._asset_kind("x.ttf") == "font" and p._asset_kind("x.svg") == "image" and p._asset_kind("x.gd") == "text", "asset kinds")
	p._tabs.current_tab = 0
	p.go_step(2)
	check_eq(p.step, 2, "steps can be stepped through")
	check(p._view.elements == published[0]["steps"][2]["diagram"], "the step's diagram is shown")
	p.go_step(999)
	check_eq(p.step, published[0]["steps"].size() - 1, "and stop at the last")
	p._view.t = 5.0
	p.go_step(p.step + 1)
	check(p._view.t == 5.0, "going past the last step with go_step doesn't replay its diagram")
	p.turn(1)
	check_eq(p.step, 0, "Next on the last step shows the first")
	p.turn(-1)
	check_eq(p.step, published[0]["steps"].size() - 1, "Previous on the first shows the last")
	for i in 30:
		await tree.process_frame   # (draws every element kind while animating in)
	p.queue_free()
	await tree.process_frame


func test_svg_editor() -> void:
	var ed: Control = load("res://svg_editor.tscn").instantiate()
	tree.root.add_child(ed)
	for i in 3:
		await tree.process_frame
	var drag := func(a: Vector2, b: Vector2) -> void:
		ed.on_press(a)
		ed.on_motion(a.lerp(b, 0.5))
		ed.on_motion(b)
		ed.on_release(b)
	ed.set_tool("rect")
	drag.call(Vector2(50, 50), Vector2(250, 150))
	check(ed.doc.shapes.size() == 1 and ed.doc.shapes[0]["type"] == "rect", "the rectangle tool draws a rectangle")
	check(is_equal_approx(float(ed.doc.shapes[0]["w"]), 200.0), "of the dragged size")
	ed.set_tool("ellipse")
	drag.call(Vector2(300, 50), Vector2(400, 150))
	ed.set_tool("star")
	drag.call(Vector2(600, 300), Vector2(600, 200))
	ed.set_tool("pen")
	for p in [Vector2(100, 300), Vector2(200, 400), Vector2(50, 450)]:
		ed.on_press(p)
		ed.on_release(p)
	ed.on_press(Vector2(100, 300))   # the first node: closes it
	ed.on_release(Vector2(100, 300))
	check(ed.doc.shapes.size() == 4 and ed.doc.shapes[3]["subs"][0]["closed"], "the pen draws a closed path")
	ed.set_tool("text")
	ed.on_press(Vector2(80, 560))
	ed.set_prop("text", "Hello")
	check(ed.doc.shapes[-1]["type"] == "text" and ed.doc.shapes[-1]["text"] == "Hello", "text is placed and typed")
	# Select and move the rectangle.
	ed.set_tool("select")
	drag.call(Vector2(150, 100), Vector2(170, 130))
	check(SvgDoc.bounds(ed.doc.shapes[0]).position.is_equal_approx(Vector2(70, 80)), "dragging moves it")
	ed.undo()
	check(SvgDoc.bounds(ed.doc.shapes[0]).position.is_equal_approx(Vector2(50, 50)), "undo puts it back")
	ed.redo()
	check(SvgDoc.bounds(ed.doc.shapes[0]).position.is_equal_approx(Vector2(70, 80)), "redo moves it again")
	# Node editing: the star becomes a path, a node moves.
	ed._select([ed.doc.shapes[2]])
	ed.set_tool("node")
	check(ed.doc.shapes[2]["type"] == "path", "editing nodes turns the star into a path")
	var n0: Vector2 = ed.doc.shapes[2]["subs"][0]["nodes"][0]["p"]
	drag.call(n0, n0 + Vector2(0, -30))
	check((ed.doc.shapes[2]["subs"][0]["nodes"][0]["p"] as Vector2).is_equal_approx(n0 + Vector2(0, -30)), "a node is dragged")
	# Right-click menus: nodes, shapes, the canvas.
	var labels := func(items: Array) -> Array:
		return items.filter(func(e): return e is Array).map(func(e): return e[0])
	var star_path: Dictionary = ed.doc.shapes[2]
	var n1: Vector2 = star_path["xf"] * star_path["subs"][0]["nodes"][1]["p"]
	var node_menu: Array = labels.call(ed.context_menu(n1, Vector2.ZERO, false))
	check(node_menu.has("Make smooth") and node_menu.has("Delete nodes") and node_menu.has("Break the path here"), "the node menu (%s)" % ", ".join(node_menu))
	check(ed.node_sel.size() == 1 and ed.node_sel[0][2] == 1, "right-clicking a node selects it")
	ed.set_nodes_smooth(true)
	check(star_path["subs"][0]["nodes"][1]["s"], "make smooth")
	var count0: int = star_path["subs"][0]["nodes"].size()
	ed.break_at_node()
	check(not star_path["subs"][0]["closed"] and star_path["subs"][0]["nodes"].size() == count0 + 1, "break: the closed path opens at the node")
	ed.undo()
	check(star_path["subs"].size() == 1 and ed.doc.shapes[2]["subs"][0]["closed"], "undo closes it again")
	ed.set_tool("select")
	var rect_menu: Array = labels.call(ed.context_menu(Vector2(100, 120), Vector2.ZERO, false))
	check(rect_menu.has("Delete") and rect_menu.has("Raise to top") and rect_menu.has("Flip horizontally"), "the shape menu")
	check(ed.sel.size() == 1 and ed.sel[0]["type"] == "rect", "right-clicking a shape selects it")
	var canvas_menu: Array = labels.call(ed.context_menu(Vector2(790, 590), Vector2.ZERO, false))
	check(canvas_menu.has("Select all") and canvas_menu.has("Export PNG..."), "the canvas menu")
	# Files.
	check(ed.save_file("user://test_drawing.svg"), "saves an SVG file")
	check(ed.export_png("user://test_drawing.png", 0.5), "exports a PNG")
	var img := Image.load_from_file(ProjectSettings.globalize_path("user://test_drawing.png"))
	check(img != null and img.get_size() == Vector2i(400, 300), "at the chosen scale (%s)" % str(img.get_size() if img else null))
	var count: int = ed.doc.shapes.size()
	ed.set_tool("select")
	ed.select_all()
	ed.delete_selection()
	check(ed.doc.shapes.is_empty(), "delete removes the selection")
	check(ed.open_file("user://test_drawing.svg") and ed.doc.shapes.size() == count, "opens it again, every object back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_drawing.svg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_drawing.png"))
	ed.dirty = false
	ed.queue_free()
	await tree.process_frame


## The Library's asset browser: everything sorted by who it belongs to.
func test_asset_browser() -> void:
	AssetCatalog.reset()
	var owners: Array = AssetCatalog.owners()
	var ids: Array = owners.map(func(o): return o["id"])
	for e in ["minoa", "athens", "sparta", "mycenae", "ionia", "independent", "pirates", "monsters", "wildlife", "galaxy"]:
		check(e in ids, "an owner in the browser: %s" % e)
	# Every ship under whoever flies it; every station under its builder.
	for o in owners:
		for c in o["categories"]:
			for en in c["entries"]:
				if c["name"] == "Ships":
					check_eq(ShipDesigns.owner_of(str(en["key"]).trim_prefix("ship:")), o["id"], "%s under %s" % [en["title"], o["name"]])
				elif c["name"] == "Stations":
					check(str(en["key"]).trim_prefix("station:") in StationArt.BY_EMPIRE[o["id"]], "%s under %s" % [en["title"], o["name"]])
	var n_ships := AssetCatalog.all_entries().filter(func(t): return t[1]["name"] == "Ships").size()
	check(n_ships >= 60, "every ship class listed (%d)" % n_ships)
	var zoo: Node2D = load("res://zoo.tscn").instantiate()
	zoo.start_browser = true
	tree.root.add_child(zoo)
	await tree.process_frame
	check(zoo.browser.visible, "the Library opens on the browser")
	check(zoo.browser.open("sparta", "Ships"), "a category opens")
	check_eq(zoo.browser.shown().size(), 15, "the Spartans' twelve ships and three capital ships")
	check(not zoo.browser.selected().is_empty(), "the first one selected")
	check(AssetCatalog.texture(zoo.browser.selected()) != null, "with a preview")
	zoo.browser._search.text = "leonidas"
	zoo.browser._show_search()
	check_eq(zoo.browser.shown().size(), 1, "search finds the Leonidas")
	zoo.view_live("SHIPS", "traced_sparta_leonidas")
	await tree.process_frame
	check(not zoo.browser.visible and zoo.ROOMS[zoo.room] == "SHIPS", "View live: the Ships room")
	check(zoo.cam.position.distance_to(zoo._spots["traced_sparta_leonidas"]) < 1.0, "centred on the ship")
	zoo.show_browser()
	check(zoo.browser.visible, "back to the browser")
	zoo.queue_free()
	await tree.process_frame


## Talos's Library: a drag on its view pans it - Talos's own screen (a
## full-screen Control) lets the mouse through to the world under it - and the
## drag follows the mouse over the interface until its button is let go.
func test_library_drag_pans_in_talos() -> void:
	var host: Control = load("res://editor.tscn").instantiate()
	tree.root.add_child(host)
	await tree.process_frame
	host.show_tool("library")
	for i in 5:
		await tree.process_frame
	var z = host.tools["library"]
	z.show_room(1)
	await tree.process_frame
	check_eq(host.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Talos's screen takes no mouse (it would swallow the Library's drags)")
	var vp := host.get_viewport()
	var p0: Vector2 = z.cam.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(900, 600)
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(press)
	var pos := Vector2(900, 600)
	for i in 20:   # (up across the top bar)
		pos += Vector2(0, -27)
		var mm := InputEventMouseMotion.new()
		mm.position = pos
		mm.relative = Vector2(0, -27)
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		vp.push_input(mm)
	await tree.process_frame
	check((z.cam.position - p0).y * z._zoom > 530.0, "the view followed the whole drag, over the bar too (%s)" % ((z.cam.position - p0) * z._zoom))
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = pos
	vp.push_input(release)
	check(not z._drag, "let go over the bar: the drag ends")
	# A release lost on the way: the next motion without the button ends it.
	vp.push_input(press)
	var loose := InputEventMouseMotion.new()
	loose.position = Vector2(950, 600)
	loose.relative = Vector2(50, 0)
	vp.push_input(loose)
	check(not z._drag, "moving with no button held ends a drag")
	host.queue_free()
	await tree.process_frame


## Lore and dialogue text in Talos shows formatted (bold, italic - not the raw
## [b] tags); a click shows the source (tags dimmed), Ctrl+B wraps the
## selection, and Esc ends the editing - not Talos.
func test_rich_text_fields() -> void:
	var got := []
	var f := RichField.new().setup("A [b]bold[/b] word.", func(t): got.append(t), 40.0)
	tree.root.add_child(f)
	await tree.process_frame
	check(not f.editing() and f._view.visible, "shown formatted at first")
	check_eq(f._view.get_parsed_text(), "A bold word.", "the tags don't show")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	f._view.gui_input.emit(click)
	await tree.process_frame
	check(not f.editing(), "a click on the text doesn't edit it")
	check(f._edit_btn.text == "Edit", "an Edit button beside it")
	f._edit_btn.pressed.emit()
	await tree.process_frame
	check(f.editing() and f._edit.text == "A [b]bold[/b] word.", "Edit: the source")
	check(f._edit_btn.text == "Done" and f._tools.visible, "Done, and B / I, while editing")
	f._edit.select(0, 14, 0, 18)   # "word"
	f._wrap("i")
	await tree.process_frame   # (a TextEdit tells of a change the next frame)
	check_eq(f.text, "A [b]bold[/b] [i]word[/i].", "Ctrl+I wraps the selection")
	check(not got.is_empty() and got[-1] == f.text, "and the change is passed on")
	f._edit_btn.pressed.emit()
	await tree.process_frame
	check(not f.editing() and f._view.get_parsed_text() == "A bold word.", "Done: formatted again")
	check(f._edit_btn.text == "Edit", "and the button says Edit again")
	f.queue_free()
	# The Lore page and the dialogue lines use it; Esc in a text field doesn't leave Talos.
	var ed: Control = load("res://editor.tscn").instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	var dm: DevMode = null
	for c in ed.get_children():
		if c is DevMode:
			dm = c
	dm.show_tab(DevMode.TABS.find("LORE"))
	await tree.process_frame
	var fields := dm.find_children("*", "RichField", true, false).filter(func(x): return x.is_visible_in_tree())
	check(fields.size() == 1, "the Lore page's text is a formatted field (%d)" % fields.size())
	if fields.size() == 1:
		check(not fields[0]._view.get_parsed_text().contains("[b]"), "shown without its tags")
		fields[0]._edit_btn.pressed.emit()
		await tree.process_frame
		var esc := InputEventAction.new()
		esc.action = "ui_cancel"
		esc.pressed = true
		dm._input(esc)
		await tree.process_frame
		check(is_instance_valid(dm) and dm.is_inside_tree() and not fields[0].editing(), "Esc ends the editing, Talos stays")
	dm.show_tab(0)
	await tree.process_frame
	check(dm.find_children("*", "RichField", true, false).filter(func(x): return x.is_visible_in_tree()).size() > 0, "the dialogue lines too")
	ed.queue_free()
	await tree.process_frame
