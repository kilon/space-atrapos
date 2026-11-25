extends VBoxContainer
## The ship's industry (Industry), shown by its devices (DeviceMenu: a device's
## own window, opened at its terminal aboard) - the REFINERY (mined fragments
## into minerals), the FABRICATOR (recipes: materials, components, spare parts,
## supplies, weapons, Upgrade Kits) and KITS (fit an upgrade yourself). The
## work goes on while you fly; the queue shows here. `only`: the pages a
## device shows (its tabs hidden when it's one).

var data: Node
var ship: Node2D

const PAGES := ["REFINERY", "FABRICATOR", "KITS"]
var _page := 0
var _cat := 0
var _kit_body := "ship"
var _body: VBoxContainer
var _queue_box: VBoxContainer
var _bars := []
var _tab_btns := []
var _t := 0.0
var only: Array = []             # (the pages shown: all when empty)
var _tabs_row: HBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for i in PAGES.size():
		var b := UI.button(PAGES[i], func():
			_page = i
			refresh(), 15)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		b.tooltip_text = PAGES[i].capitalize() + "\n" + ["Turns the fragments you've mined into their minerals; it works on while you fly.",
			"Makes things from minerals and goods: materials, components, spare parts, supplies, weapons, Upgrade Kits.",
			"Fits an Upgrade Kit you carry to one of your ship's or automaton's stats."][i]
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 36)
		tabs.add_child(b)
		_tab_btns.append(b)
	add_child(tabs)
	_tabs_row = tabs
	show_only(only)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(row)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	row.add_child(_body)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	right.add_child(UI.section("AT WORK"))
	_queue_box = VBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 4)
	right.add_child(_queue_box)


## The pages a device shows (all when empty): the others' tabs hidden - the row too when it's one.
func show_only(pages: Array) -> void:
	only = pages
	if _tabs_row == null:
		return
	for i in _tab_btns.size():
		_tab_btns[i].visible = pages.is_empty() or i in pages
	_tabs_row.visible = pages.size() != 1
	if not pages.is_empty() and not _page in pages:
		_page = int(pages[0])


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var q := Industry.queue_of(data)
	if q.size() != _bars.size():
		_fill_queue()
	elif not q.is_empty() and _bars.size() > 0 and _bars[0] is ProgressBar:
		var j: Dictionary = q[0]
		_bars[0].value = (int(j["done"]) + float(j["t"]) / maxf(0.01, Industry.unit_time(data, j))) / maxf(1.0, int(j["n"]))
	if _t > 1.0:
		_t = 0.0
		_fill_queue()


func refresh() -> void:
	if _body == null:
		return
	UI.clear(_body)
	for i in _tab_btns.size():
		_tab_btns[i].set_pressed_no_signal(i == _page)
	match _page:
		0:
			_refinery()
		1:
			_fabricator()
		2:
			_kits()
	_fill_queue()


func _fill_queue() -> void:
	UI.clear(_queue_box)
	_bars = []
	var q := Industry.queue_of(data)
	if q.is_empty():
		_queue_box.add_child(UI.label("Nothing - the refinery and the fabricator are idle.", 14, UI.TEXT_DIM))
		return
	for i in q.size():
		var j: Dictionary = q[i]
		var name: String = ("Refining " + Items.display_name(j["id"]).to_lower()) if j["kind"] == "refine" else ("Making " + str(Industry.recipe(j["id"])[0]))
		var h := HBoxContainer.new()
		var l := UI.label("%s  %d / %d%s" % [name, int(j["done"]), int(j["n"]), "  (hold full)" if j.get("waiting", false) else ""], 14, Color.WHITE if i == 0 else UI.TEXT_DIM)
		l.size_flags_horizontal = SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(l)
		var x := UI.button("✕", func():
			Industry.cancel(data, i)
			refresh(), 13)
		x.tooltip_text = "Stop it: what isn't made yet is given back."
		h.add_child(x)
		_queue_box.add_child(h)
		if i == 0:
			var bar := ProgressBar.new()
			bar.max_value = 1.0
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, 8)
			_queue_box.add_child(bar)
			_bars.append(bar)
		else:
			_bars.append(null)


func _need_equipment(id: String) -> bool:
	if data.has_equipment(id):
		return false
	_body.add_child(UI.note("No %s fitted - outfitters sell them (SYSTEMS). %s" % [Items.EQUIPMENT[id]["name"].to_lower(), Items.EQUIPMENT[id]["desc"]], 15, 800))
	return true


func _refinery() -> void:
	_body.add_child(UI.section("REFINERY  ·  fragments into minerals"))
	if _need_equipment("refinery"):
		return
	_body.add_child(UI.note("Each fragment becomes a unit of its mineral (rubble: scrap, now and then a mineral), %.1f s a unit (the reactor's refinery upgrade makes it faster)." % (Industry.REFINE_TIME / (1.0 + data.mod("refine_speed"))), 14, 800))
	var frags: Array = data.held_items().filter(func(x): return Mining.is_frag(x))
	if frags.is_empty():
		_body.add_child(UI.label("No fragments in the hold - mine an asteroid's veins (prospect it with a right-click, then hold the button on it).", 15, UI.TEXT_DIM))
		return
	for id in frags:
		var n: int = data.count(id)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var icon := ItemSlot.make(id, n, 40.0)
		h.add_child(icon)
		var m := Mining.mineral_of(id)
		var l := UI.label("%s  ×%d   →  %s" % [Items.display_name(id), n, "scrap and odd minerals" if m == "rubble" else "%d %s (%d dr each)" % [n, Items.display_name(m), int(Items.info(m).get("value", 0))]], 15, Color.WHITE)
		l.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(l)
		for k in [10, n]:
			if k > n or (k == 10 and n <= 10):
				continue
			var b := UI.button("Refine %s" % ("all" if k == n else str(k)), func():
				Industry.order(data, "refine", id, k)
				refresh(), 14)
			h.add_child(b)
		_body.add_child(h)


func _fabricator() -> void:
	_body.add_child(UI.section("FABRICATOR  ·  make things from minerals and goods"))
	if _need_equipment("fabricator"):
		return
	var cats := HBoxContainer.new()
	cats.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for i in Industry.CATEGORIES.size():
		var b := UI.button(Industry.CATEGORIES[i], func():
			_cat = i
			refresh(), 14)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == _cat
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		cats.add_child(b)
	_body.add_child(cats)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	_body.add_child(grid)
	for id in Industry.RECIPES:
		var r: Array = Industry.RECIPES[id]
		if r[1] != Industry.CATEGORIES[_cat]:
			continue
		var card := PanelContainer.new()
		UI.light_panel(card)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		card.add_child(h)
		h.add_child(ItemSlot.make(r[2][0], int(r[2][1]), 44.0))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(v)
		var worth := int(Items.info(r[2][0]).get("value", 0)) * int(r[2][1])
		v.add_child(UI.label("%s%s  ·  %.0f s%s" % [r[0], ("  ×%d" % int(r[2][1])) if int(r[2][1]) > 1 else "", float(r[4]), ("  ·  sells ~%d dr" % worth) if worth > 0 else ""], 15, Color.WHITE))
		var ins := []
		for k in r[3]:
			var have: int = data.count(k)
			ins.append("%s %d/%d" % [Items.display_name(k), have, int(r[3][k])])
		var il := UI.label(",  ".join(ins), 13, UI.TEXT_DIM)
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(il)
		var can := Industry.can_make(data.items, id)
		var bs := HBoxContainer.new()
		for k in [1, 5]:
			var b := UI.button("Make %d" % k, func():
				Industry.order(data, "fab", id, k)
				refresh(), 13)
			b.disabled = can < k
			bs.add_child(b)
		v.add_child(bs)
		grid.add_child(card)


func _kits() -> void:
	_body.add_child(UI.section("UPGRADE KITS  ·  fit a component upgrade yourself"))
	var held := []
	for k in Industry.KITS:
		held.append("%s ×%d" % [Items.display_name(k), data.count(k)])
	_body.add_child(UI.note("You carry: %s. A Mk I raises a stat from level 0 or 1, a Mk II from 2 or 3, a Mk III from 4 to the top. The fabricator makes them; stations upgrade for drachmas (Workshop > Upgrades)." % ", ".join(held), 14, 900))
	var top := HBoxContainer.new()
	for w in ["ship", "automaton"]:
		var b := UI.button(Parts.BODIES[w]["name"].to_upper(), func():
			_kit_body = w
			refresh(), 14)
		b.toggle_mode = true
		b.button_pressed = w == _kit_body
		b.tooltip_text = "The stats of your %s the kits can raise." % ("ship" if w == "ship" else "automaton")
		top.add_child(b)
	_body.add_child(top)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	_body.add_child(grid)
	for st in Upgrades.list(_kit_body):
		var lvl := Upgrades.level(data.upgrades, _kit_body, st["id"])
		var kit := ""
		for k in Industry.KITS:
			if Industry.kit_fits(k, data.upgrades, _kit_body, st["id"]):
				kit = k
		var h := HBoxContainer.new()
		var l := UI.label("%s · %s  %d/%d" % [Parts.info(_kit_body, st["part"])["name"], st["name"], lvl, Upgrades.MAX_LEVEL], 13, Color.WHITE if lvl < Upgrades.MAX_LEVEL else UI.TEXT_DIM)
		l.size_flags_horizontal = SIZE_EXPAND_FILL
		l.clip_text = true
		h.add_child(l)
		var b := UI.button("Fit %s" % Items.display_name(kit).trim_prefix("Upgrade Kit ") if kit != "" else "-", func():
			if Industry.fit_kit(data, kit, _kit_body, st["id"]):
				GameLog.post("Upgrade Kit fitted: %s's %s to level %d." % [Parts.info(_kit_body, st["part"])["name"], str(st["name"]).to_lower(), Upgrades.level(data.upgrades, _kit_body, st["id"])], "good")
				if ship and ship.has_method("apply_tech"):
					ship.apply_tech()
			refresh(), 12)
		b.disabled = kit == "" or data.count(kit) <= 0
		if kit == "":
			b.tooltip_text = "%s: at its best - no kit raises it further." % st["name"] if lvl >= Upgrades.MAX_LEVEL else "%s: no kit fits it." % st["name"]
		else:
			b.tooltip_text = "Fits an %s (you have %d): %s up to level %d." % [Items.display_name(kit), data.count(kit), str(st["name"]).to_lower(), lvl + 1]
		b.custom_minimum_size = Vector2(90, 0)
		h.add_child(b)
		h.custom_minimum_size = Vector2(380, 0)
		grid.add_child(h)
