extends TestCase
## Every control you can use has a tooltip: each screen is built (the title menu
## and its settings pages, Mods, Patch Notes, the Mod Editor, Talos and each of
## its tools, the Live Editor's tabs over a game, the game's HUD, the Automaton,
## the Station Menu) and walked; a visible button, field, slider, list or tab
## bar with no tooltip fails with its path. Help lives in tooltips (no helper
## text on screen), so nothing you can click goes without one.
##
## Covered: its own tooltip_text (or PinTips' "tip" / "tip_fn" meta); a spin
## box's own field (internal) through the spin box; an ItemList / TabBar whose
## every item has its own tooltip; a control that lets the mouse through
## (mouse_filter not STOP) under one that has a tooltip - Godot shows the
## parent's then.

var _old_system := ""
var _old_data := {}
## The controls seen so far on the screen being walked (path -> true): the report's count.
static var seen := {}


func setup() -> void:
	_old_system = Galaxy.current_system
	LiveEdits.load_all()
	_old_data = LiveEdits.data.duplicate(true)


func teardown() -> void:
	Galaxy.current_system = _old_system
	Cosmos.arrive_from = ""
	LiveEdits.data = _old_data
	LiveEdits.dirty = false
	EditTarget.mod_id = ""
	Engine.time_scale = 1.0
	tree.paused = false


static func _interactive(c: Control) -> bool:
	return c is BaseButton or c is LineEdit or c is TextEdit or c is SpinBox or c is Slider \
		or c is ItemList or c is Tree or c is TabBar or c is TabContainer


static func _own_tip(c: Control) -> bool:
	if c.tooltip_text.strip_edges() != "" or c.has_meta("tip_fn"):
		return true
	if c.has_meta("tip") and str(c.get_meta("tip")) != "":
		return true
	if c is ItemList:
		var il := c as ItemList
		if il.item_count == 0:
			return false
		for i in il.item_count:
			if il.get_item_tooltip(i) == "":
				return false
		return true
	if c is TabBar:
		var tb := c as TabBar
		if tb.tab_count == 0:
			return false
		for i in tb.tab_count:
			if tb.get_tab_tooltip(i) == "":
				return false
		return true
	if c is TabContainer:
		var tb2 := (c as TabContainer).get_tab_bar()
		if tb2.tab_count == 0:
			return false
		for i in tb2.tab_count:
			if tb2.get_tab_tooltip(i) == "":
				return false
		return true
	return false


static func _covered(c: Control) -> bool:
	if _own_tip(c):
		return true
	var n: Control = c
	while n.mouse_filter != Control.MOUSE_FILTER_STOP or n == c and c.mouse_filter != Control.MOUSE_FILTER_STOP:
		if n.top_level:
			return false
		n = n.get_parent_control()
		if n == null:
			return false
		if _own_tip(n):
			return true
	return false


## The visible controls under `root` you can use with no tooltip, into `out`
## (path relative to root -> a description), keyed so revisits don't repeat.
static func scan(root: Node, out: Dictionary) -> void:
	_walk(root, root, out)


static func _walk(root: Node, n: Node, out: Dictionary) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Window and not (n as Window).visible:
		return
	if n is Control and _interactive(n) and (n as Control).is_visible_in_tree():
		seen[str(n.get_path())] = true
	if n is Control and _interactive(n) and (n as Control).is_visible_in_tree() and not _covered(n):
		var c := n as Control
		var what: String = c.get_class()
		var t = c.get("text")
		if t is String and t != "":
			what += " \"%s\"" % t.left(30)
		elif c.get("placeholder_text") is String and c.placeholder_text != "":
			what += " (%s)" % c.placeholder_text.left(30)
		var sc: Script = c.get_script()
		if sc and sc.resource_path != "":
			what += " [%s]" % sc.resource_path.get_file()
		out[str(root.get_path_to(c))] = what
	for k in n.get_children():
		_walk(root, k, out)


func _report(screen: String, out: Dictionary) -> void:
	print("  tooltips: %s - %d controls, %d without a tooltip" % [screen, seen.size(), out.size()])
	seen.clear()
	if out.is_empty():
		return
	var lines: Array = []
	for p in out:
		lines.append("    %s  %s" % [out[p], p])
	lines.sort()
	check(false, "%s: %d controls without a tooltip:\n%s" % [screen, out.size(), "\n".join(lines)])


func _frames(n := 2) -> void:
	for i in n:
		await tree.process_frame


# --- The title screen ---------------------------------------------------------

func test_title_menu_and_settings() -> void:
	var m: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	tree.root.add_child(m)
	await _frames(3)
	var out := {}
	scan(m, out)
	m._open_settings()
	await _frames()
	for i in m.SETTINGS_TABS.size():
		m.show_settings_tab(i)
		await _frames()
		scan(m, out)
	m._close_settings()
	m._open_crt()
	await _frames()
	scan(m, out)
	m._close_crt()
	m._open_slots("load")
	await _frames()
	scan(m, out)
	m._close_slots()
	_report("title menu", out)
	# The Archive (every book of the game), each book.
	out = {}
	var a: Archive = Archive.open(m, "guide")
	await _frames(3)
	for b in Archive.BOOKS:
		a.open_book(str(b["id"]))
		await _frames()
		scan(a, out)
	_report("Archive", out)
	a.get_parent().get_parent().queue_free()
	m.queue_free()
	await _frames()


# --- Mods, Patch Notes, the Mod Editor -----------------------------------------

func test_mods_screen() -> void:
	var id := Mods.create("Tooltip Test Mod")
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var s: Control = load("res://scripts/ui/mods_screen.gd").open_over(host)
	await _frames()
	var out := {}
	scan(s, out)
	_report("mods screen", out)
	host.queue_free()
	Mods.remove(id)
	await _frames()


func test_patch_notes() -> void:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(host)
	var notes: Control = load("res://scripts/editor/patcher.gd").open_over(host)
	await _frames(3)
	var out := {}
	scan(notes, out)
	_report("patch notes", out)
	host.queue_free()
	await _frames()


func test_mod_editor() -> void:
	var ed: Control = load("res://scenes/editor/mod_editor.tscn").instantiate()
	tree.root.add_child(ed)
	await _frames()
	var out := {}
	scan(ed, out)
	var id: String = ed.new_mod("Tooltip Editor Mod")
	await _frames()
	scan(ed, out)
	ed.override("res://data/themes.json")
	await _frames()
	scan(ed, out)
	ed.dirty = false
	for i in range(1, ed.TABS.size()):   # (the tools it embeds)
		ed.show_tab(i)
		await _frames(3)
		scan(ed, out)
	ed.show_tab(0)
	_report("mod editor", out)
	ed.queue_free()
	await _frames()
	Mods.remove(id)


# --- Talos ----------------------------------------------------------------------

func test_talos_tools() -> void:
	var host: Control = load("res://scenes/editor/editor.tscn").instantiate()
	tree.root.add_child(host)
	await _frames(3)
	for t in TalosNav.TOOLS:
		if not t is Array:
			continue
		var id: String = t[0]
		host.show_tool(id)
		await _frames(3)
		var out := {}
		var root: Node = host.tools.get(id, host.editor)
		scan(root, out)
		await _deeper(id, root, out)
		_report("Talos: " + id, out)
	for id in host.tools:
		host.tools[id].set("dirty", false)
	host.queue_free()
	await _frames()


## A tool's screens past its first: a part picked, edit mode, the shapes, the materials,
## a bone picked, an effect picked, the right-click menus.
func _deeper(id: String, t: Node, out: Dictionary) -> void:
	match id:
		"mesh":
			t.add_primitive("box")
			await _frames()
			scan(t, out)
			t.add_primitive("sphere")
			t.select_part(t.parts()[0], true)   # (two picked: the booleans)
			await _frames()
			scan(t, out)
			t.select_part(t.parts()[0])
			var pm: PopupPanel = t.menu(t.view.size * 0.5)
			await _frames()
			scan(pm, out)
			pm.hide()
			t.set_left_tab("shapes")
			await _frames()
			scan(t, out)
			t.set_left_tab("materials")   # (the material library; the MATERIAL panel with a full material)
			t.mat_tools.pick("preset:Gold")
			await _frames()
			scan(t, out)
			t.set_left_tab("models")
			t.enter_edit(true)
			await _frames()
			scan(t, out)
			t.select_all(true)
			await _frames()
			scan(t, out)
			pm = t.menu(t.view.size * 0.5)
			await _frames()
			scan(pm, out)
			pm.hide()
			t.toggle_edit()
			t.dirty = false
		"anim":
			t.select_bone(1)
			await _frames()
			scan(t, out)
		"fx":
			t.select(str(Fx.names()[0]))
			await _frames()
			scan(t, out)


# --- In a game: the Live Editor, the HUD, the Automaton, the Station Menu -------

func _cosmos() -> Cosmos:
	if Galaxy.systems.is_empty():
		Galaxy._new_game_begin(true, false)
	Galaxy.current_system = "atrapos"
	Cosmos.arrive_from = ""
	var c: Cosmos = load(Cosmos.SCENE).instantiate()
	tree.root.add_child(c)
	var t0 := Time.get_ticks_msec()
	while not c.build_settled() and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	return c


func test_in_game_screens() -> void:
	var c := await _cosmos()
	# The HUD.
	var out := {}
	if c.hud:
		c.hud.visible = true
		scan(c.hud, out)
	if c.hud2d:
		scan(c.hud2d, out)
	_report("HUD", out)
	# The Automaton (Tab): each of its tabs.
	out = {}
	c.open_computer(0)
	await _frames()
	var M: GDScript = load("res://scripts/ui/ship_menu.gd")
	for i in M.SHOWN:
		c._computer.show_tab(i)
		await _frames()
		scan(c._computer, out)
		if i == M.MAP_TAB:
			var maps: Control = c._computer.maps()
			for k in maps.SUBS.size():
				maps.show_sub(k)
				await _frames()
				scan(c._computer, out)
	c._computer.close()
	_report("Automaton", out)
	# The Station Menu, at a station of this system.
	out = {}
	var st: Node = null
	for n in c.find_children("*", "CosmosStation", true, false):
		st = n
		break
	if st:
		c.dock_station = st
		c.open_service(1)
		await _frames()
		var S: GDScript = load("res://scripts/ui/station_menu.gd")
		var sm: Control = c._station_menu
		for i in S.TABS.size():
			sm.show_tab(i)
			await _frames()
			scan(sm, out)
		# (the pages' own tabs: the workshop's two bodies and fuel, outfitting's sections)
		sm.show_tab(0)
		for v in [["automaton", 0], ["ship", 1]]:
			sm._up_body = v[0]
			sm._workshop_page = v[1]
			sm.refresh()
			await _frames()
			scan(sm, out)
		sm._workshop_page = 0
		sm.show_tab(2)
		for k in S.OUTFIT_TABS.size():
			sm._outfit_tab = k
			sm.refresh()
			await _frames()
			scan(sm, out)
		sm._outfit_tab = 0
		c._station_menu.close()
		c.dock_station = null
	_report("station menu", out)
	# The ship's devices, the builder's menu, a chest.
	out = {}
	for k in ["refinery", "fabricator"]:
		c.open_device(k)
		await _frames()
		scan(c._device_menu, out)
		if k == "fabricator":   # (its Kits page too)
			var pg: Node = c._device_menu.find_children("*", "", true, false).filter(func(n): return n.get("_kit_body") != null)[0]
			pg._page = 2
			pg.refresh()
			await _frames()
			scan(c._device_menu, out)
		c._device_menu.close()
	if c.builds:
		c.open_build_menu()
		await _frames()
		scan(c._build_menu, out)
		c._build_menu.close()
	c.open_chest({"inv": {"iron_ore": 3}})
	await _frames()
	scan(c._chest_menu, out)
	c._chest_menu.close()
	_report("devices, builder, chest", out)
	c.queue_free()
	await _frames()


func test_live_editor_tabs() -> void:
	var c := await _cosmos()
	LiveEditor.toggle(c)
	await _frames()
	var ed: LiveEditor = LiveEditor.current
	var out := {}
	scan(ed, out)
	# A box of our own (object, model, material, particles), a character
	# (animation) and a thing with solids (collision).
	var target := MeshInstance3D.new()
	target.mesh = BoxMesh.new()
	target.material_override = StandardMaterial3D.new()
	var holder := Node3D.new()
	holder.set_meta("edit_key", "test/tooltips")
	holder.add_child(target)
	c.world.add_child(holder)
	var shader_thing: Node = null
	var character: Node = null
	var solid: Node = null
	var tabs: Dictionary = ed._scripts
	for n in c.find_children("*", "", true, false):
		if character == null and n.has_meta("model_id") and tabs.has("anim") and tabs["anim"].handles(n):
			character = n
		if solid == null and n is Node3D and tabs.has("collision") and tabs["collision"].handles(n):
			solid = n
		if shader_thing == null and n is MeshInstance3D and (n as MeshInstance3D).get_active_material(0) is ShaderMaterial:
			shader_thing = n
	for n in [target, shader_thing, character, solid]:
		if n == null:
			continue
		ed.select(n)
		await _frames()
		for b in ed._tab_bar.get_children():
			var id := str(b.name).trim_prefix("Tab_")
			ed.show_tab(id)
			await _frames()
			scan(ed, out)
			if id == "fx" and n == target:
				var fx_tab = ed.tab()
				fx_tab.add_here("mining_sparks")
				await _frames()
				fx_tab._edit("mining_sparks")
				await _frames()
				scan(ed, out)
			if id == "collision":
				ed.tab()._select(0, false)
				await _frames()
				scan(ed, out)
	_report("Live Editor", out)
	LiveEdits.forget("test/tooltips")
	ed._close_now()
	await _frames()
	c.queue_free()
	await _frames()


## Talos's tooltips show on every tool: their layer is Talos's own, never hidden with
## the data editor when another tool shows (it was - and every other tool had none).
func test_talos_tooltips_show_on_every_tool() -> void:
	var host: Control = load("res://scenes/editor/editor.tscn").instantiate()
	tree.root.add_child(host)
	for i in 10:
		await tree.process_frame
	check(host.tips != null and host.tips.get_parent() == host, "the tooltips are Talos's own")
	for id in TalosNav.TOOL_IDS + ["dialogue"]:
		host.show_tool(id)
		await tree.process_frame
		check(host.tips.visible and host.tips.is_inside_tree(), "%s: the tooltips' layer shows" % id)
		check_eq(host.tips.screen_doc, str(host.DOCS.get("" if id == "dialogue" else id, "")), "%s: its tooltips link to its own help" % id)
	host.queue_free()
	await tree.process_frame


## Live coding: Talos's tools built again with new code, reopening what they had (LiveLink calls it).
func test_talos_tools_rebuild_live() -> void:
	var host: Control = load("res://scenes/editor/editor.tscn").instantiate()
	tree.root.add_child(host)
	for i in 10:
		await tree.process_frame
	host.show_tool("mesh")
	await tree.process_frame
	var old: Node = host.tools["mesh"]
	old.open_now("res://art/pirate_3d/pirate.glb")
	var kept: Array = host.rebuild_tools()
	for i in 3:
		await tree.process_frame
	var fresh: Node = host.tools["mesh"]
	check(kept.is_empty() and fresh != old and is_instance_valid(fresh), "the mesh editor made anew")
	check(fresh.path == "res://art/pirate_3d/pirate.glb", "with the model it had open")
	check(host.current == "mesh" and fresh.position.x == 0.0, "and shown")
	fresh.dirty = true
	check(host.rebuild_tools() == ["mesh"], "unsaved work: left as it is")
	host.queue_free()
	await tree.process_frame
