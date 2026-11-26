class_name Comms
## The comms window: a dinosaur-headed contact's portrait, who they are, what
## they say and your reply options. Pauses the game while open.
## options: [[label, Callable or null], ...] - each closes the window.


static func open(owner: Node, seed_: String, empire: String, role_line: String, text: String, options: Array, species := "", person := "") -> void:
	var tree := owner.get_tree()
	var was_paused := tree.paused
	tree.paused = true
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	owner.add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var col := Galaxy.empire_color(empire) if empire != "" else NeonTheme.HEAD
	var box := UI.modal(root, col, Vector2(860, 0))
	var head := UI.label("INCOMING TRANSMISSION", 15, col.lightened(0.3))
	box.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var pic := Portrait.new().setup(seed_, empire, species, person)
	pic.custom_minimum_size = Vector2(220, 264)
	row.add_child(pic)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	right.add_child(UI.label(pic.person_name.to_upper(), 26, Color.WHITE))
	var who := UI.label("%s  ·  %s" % [pic.species_name(), role_line], 14, UI.TEXT_DIM)
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(who)
	var msg := RichTextLabel.new()
	msg.bbcode_enabled = true
	msg.fit_content = true
	msg.custom_minimum_size = Vector2(560, 110)
	msg.add_theme_font_size_override("normal_font_size", 18)
	msg.text = "[i]\"%s\"[/i]" % text
	right.add_child(msg)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	right.add_child(buttons)
	var close := func():
		Voice.stop()
		tree.paused = was_paused
		layer.queue_free()
	if options.is_empty():
		options = [["Close channel", null]]
	var first: Button = null
	for o in options:
		var cb: Variant = o[1]
		var b := UI.button(o[0], func():
			close.call()
			if cb is Callable:
				(cb as Callable).call(), 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		buttons.add_child(b)
		if first == null:
			first = b
	UI.scale_fonts(root, "menu", 1.5)
	Voice.speak(text, pic.person_name)   # (if the line has a recording)
	if first:
		first.grab_focus()
