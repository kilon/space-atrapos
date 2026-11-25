extends SceneTree
## Every Library room: the name plates whose text overlaps another's, and
## (with a window) a screenshot of each room's whole layout.
##   godot --path . --resolution 1600x900 -s external/playtests/library_overlaps.gd -- [OUT_DIR]
func _init():
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 and not args[0].begins_with("--") else ""
	await process_frame
	var art = root.get_node("ProcArt")
	while not art.ready_done: await process_frame
	var zoo = load("res://zoo.tscn").instantiate()
	root.add_child(zoo)
	for i in 10: await process_frame
	var total := 0
	for r in zoo.ROOMS.size():
		zoo.show_room(r)
		for i in 20: await process_frame
		var hits: Array = _overlaps(zoo)
		total += hits.size()
		print("%-11s %3d plates, %d overlaps" % [zoo.ROOMS[r], zoo.labels.get_child_count(), hits.size()])
		for h in hits.slice(0, 12):
			print("     %s  <->  %s" % [h[0], h[1]])
		if out != "" and DisplayServer.get_name() != "headless":
			# Fit the whole room: frame every plate.
			var box := Rect2()
			var first := true
			for l in zoo.labels.get_children():
				if l is Label:
					box = Rect2(l.position, l.size) if first else box.merge(Rect2(l.position, l.size))
					first = false
			zoo.cam.position = box.get_center()
			var z: float = minf(root.size.x / maxf(box.size.x, 1.0), root.size.y / maxf(box.size.y, 1.0)) * 0.95
			zoo._zoom = z
			zoo.cam.zoom = Vector2(z, z)
			for i in 5: await process_frame
			root.get_texture().get_image().save_png(out.path_join("library_%d_%s.png" % [r, zoo.ROOMS[r].to_lower()]))
	print("TOTAL OVERLAPS: %d" % total)
	quit()


## Text rects (what's drawn, not the label's box) that overlap.
static func _overlaps(zoo) -> Array:
	var rects := []
	for l in zoo.labels.get_children():
		if l is Label and l.visible and l.text.strip_edges() != "":
			rects.append([l.text.replace("\n", " ").left(40), _text_rect(l)])
	var hits := []
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i][1].intersects(rects[j][1]):
				hits.append([rects[i][0], rects[j][0]])
	return hits


static func _text_rect(l: Label) -> Rect2:
	var font: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	var sz := font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, l.size.x, fs)
	return Rect2(l.position + Vector2((l.size.x - sz.x) / 2.0, 0), sz)
