extends TestCase
## The controls (Keybinds): no two actions on one key - not in the defaults, and the
## Controls screen refuses a key another action of the game already uses.


func test_no_clashes_in_the_defaults() -> void:
	var out := []
	for a in Keybinds.ACTIONS:
		for spec in a[3]:
			if str(spec) == "":
				continue
			for o in Keybinds.clashes(str(a[0]), str(spec)):
				out.append("%s: %s / %s" % [spec, a[0], o])
	check(out.is_empty(), "no key on two of the game's actions at once (%s)" % ", ".join(out))
	var g := ""
	var u := ""
	for a in Keybinds.ACTIONS:
		if a[0] == "galaxy_map":
			g = str(a[3][0])
		elif a[0] == "stand_up":
			u = str(a[3][0])
	check(g == "k:G" and u == "k:U", "G the galaxy map, U up from the pilot's seat (%s, %s)" % [g, u])


func test_controls_screen_refuses_a_clash() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	var i := src.find("var others := Keybinds.clashes(id, spec)")
	var j := src.find("Keybinds.set_bind(id, _listen_slot, spec)")
	check(i >= 0 and j > i and src.substr(i, j - i).contains("if others.is_empty()"), "a rebind: set only when nothing else uses the key")
