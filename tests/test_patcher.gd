extends TestCase
## The Patcher (the title screen's Patch Notes): every published patch and version
## reads well - its diagrams legible, its code review complete and explained.


func test_patch_diagrams_readable() -> void:
	var view = load("res://scripts/editor/patcher.gd").PatchView
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
	var p: Control = load("res://scenes/editor/patcher.tscn").instantiate()
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
		if v["patches"].is_empty():
			check(p._page_patch() == -1, "version %s: new, no patches yet - shown, nothing to open" % v["id"])
			continue
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
