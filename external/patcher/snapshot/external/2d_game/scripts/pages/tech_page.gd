extends VBoxContainer
## Ship Computer tab: the tech tree. Branches are columns, tiers are rows;
## each tech needs the one above it. Click an available tech to research it.

var data: Node
var ship: Node2D

var _header: Label
var _tree: TechTreeView
var _details: Label


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_header = UI.label("", 17, UI.GOLD)
	add_child(_header)
	_tree = TechTreeView.new()
	_tree.page = self
	_tree.size_flags_horizontal = SIZE_EXPAND_FILL   # (the cards widen to the page)
	add_child(_tree)
	_details = UI.label("Hover a technology for details. Click to research it.", 15, UI.TEXT_DIM)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size = Vector2(0, 60)
	add_child(_details)


func refresh() -> void:
	_header.text = "Drachmas: %d      Data Cores: %d      Researched: %d / %d" % [
		data.credits, data.count("data_core"), data.tech.size(), Tech.TECHS.size()]
	_tree.update_layout()


func show_details(id: String) -> void:
	if id == "":
		return
	var t: Dictionary = Tech.TECHS[id]
	var state: String = data.tech_state(id)
	var status := ""
	match state:
		"owned":
			status = "Researched."
		"locked":
			status = "Requires %s first." % Tech.TECHS[Tech.prerequisite(id)]["name"]
		"available":
			status = "Click to research." if data.can_afford_tech(id) else "Not enough drachmas or Data Cores."
	_details.text = "%s  -  %s\n%s  %s" % [t["name"], t["short"], t["desc"], status]


func research(id: String) -> void:
	if data.unlock_tech(id):
		_details.text = "%s researched!  %s" % [Tech.TECHS[id]["name"], Tech.TECHS[id]["short"]]
	else:
		show_details(id)
	refresh()


## Custom-drawn tree: cards with connecting lines.
class TechTreeView extends Control:
	const BASE_CARD := Vector2(220, 92)
	const GAP := Vector2(26, 52)
	const TOP := 40.0

	## Card size grows with the "Menus & panels" text size (width only a
	## little, so the tree still fits the window; text shrinks to fit).
	var CARD := BASE_CARD
	var _sy := 1.0

	var page: Node
	var _hover := ""

	## The widest a card gets when the page has room (px).
	const MAX_CARD_W := 340.0

	func _init() -> void:
		update_layout()
		mouse_exited.connect(func(): _hover = ""; queue_redraw())
		resized.connect(_fit_width)

	func update_layout() -> void:
		var s := Settings.font_scale("menu")
		CARD = Vector2(BASE_CARD.x * clampf(s, 1.0, 1.1), BASE_CARD.y * clampf(s, 0.85, 2.6))
		_sy = CARD.y / BASE_CARD.y
		var cols := Tech.BRANCHES.size()
		custom_minimum_size = Vector2(cols * CARD.x + (cols - 1) * GAP.x, TOP * _sy + 3 * CARD.y + 2 * GAP.y)
		_fit_width()
		queue_redraw()

	## The cards share the width the page gives the tree (no wider than MAX_CARD_W).
	func _fit_width() -> void:
		var cols := Tech.BRANCHES.size()
		var least := custom_minimum_size.x
		var w := (maxf(size.x, least) - (cols - 1) * GAP.x) / cols
		CARD.x = clampf(w, (least - (cols - 1) * GAP.x) / cols, MAX_CARD_W)
		queue_redraw()

	func card_rect(id: String) -> Rect2:
		var t: Dictionary = Tech.TECHS[id]
		var col := 0
		for i in Tech.BRANCHES.size():
			if Tech.BRANCHES[i]["id"] == t["branch"]:
				col = i
		return Rect2(Vector2(col * (CARD.x + GAP.x), TOP * _sy + t["tier"] * (CARD.y + GAP.y)), CARD)

	func _id_at(pos: Vector2) -> String:
		for id in Tech.TECHS:
			if card_rect(id).has_point(pos):
				return id
		return ""

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var id := _id_at(event.position)
			if id != _hover:
				_hover = id
				page.show_details(id)
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var id := _id_at(event.position)
			if id != "":
				page.research(id)
			accept_event()

	func _draw() -> void:
		var data: Node = page.data
		var font := ThemeDB.fallback_font

		# Branch headers.
		for i in Tech.BRANCHES.size():
			var b: Dictionary = Tech.BRANCHES[i]
			var x := i * (CARD.x + GAP.x)
			draw_string(font, Vector2(x, 24 * _sy), b["name"], HORIZONTAL_ALIGNMENT_CENTER, CARD.x, Settings.fs("menu", 18), b["color"])

		# Connections.
		for id in Tech.TECHS:
			var pre := Tech.prerequisite(id)
			if pre == "":
				continue
			var a := card_rect(pre)
			var b := card_rect(id)
			var done: bool = data.has_tech(pre)
			var col := Tech.branch_color(Tech.TECHS[id]["branch"])
			draw_line(Vector2(a.get_center().x, a.end.y), Vector2(b.get_center().x, b.position.y),
					Color(col, 0.8 if done else 0.25), 3.0 if done else 2.0, true)

		# Cards.
		for id in Tech.TECHS:
			var t: Dictionary = Tech.TECHS[id]
			var r := card_rect(id)
			var state: String = data.tech_state(id)
			var col := Tech.branch_color(t["branch"])
			var affordable: bool = data.can_afford_tech(id)

			var bg := NeonTheme.BG
			var border := Color(0.3, 0.33, 0.38)
			var text_col := Color(0.55, 0.57, 0.6)
			match state:
				"owned":
					bg = Color(col.r * 0.18, col.g * 0.18, col.b * 0.18)
					border = col
					text_col = Color.WHITE
				"available":
					border = col if affordable else Color(col, 0.45)
					text_col = Color.WHITE if affordable else NeonTheme.TEXT
			if id == _hover:
				bg = bg.lightened(0.08)
			draw_rect(r, bg)
			draw_rect(Rect2(r.position, Vector2(5, r.size.y)), Color(col, 0.9 if state != "locked" else 0.3))
			draw_rect(r, border, false, 2.5 if state == "owned" else 1.5)

			var x := r.position.x + 14
			var w := r.size.x - 22
			draw_string(font, Vector2(x, r.position.y + 26 * _sy), t["name"], HORIZONTAL_ALIGNMENT_LEFT, w,
					UI.fit_size(font, t["name"], Settings.fs("menu", 17), w), text_col)
			draw_string(font, Vector2(x, r.position.y + 50 * _sy), t["short"], HORIZONTAL_ALIGNMENT_LEFT, w,
					UI.fit_size(font, t["short"], Settings.fs("menu", 13), w), Color(text_col, 0.8))
			var cost := ""
			var cost_col := UI.GOLD
			match state:
				"owned":
					cost = "RESEARCHED"
					cost_col = col
				_:
					cost = "%d dr" % t["cost"]
					if t["cores"] > 0:
						cost += "  +  %d Data Core%s" % [t["cores"], "s" if t["cores"] > 1 else ""]
					if state == "locked":
						cost_col = Color(0.5, 0.5, 0.55)
					elif not affordable:
						cost_col = Color(1.0, 0.45, 0.4)
			draw_string(font, Vector2(x, r.position.y + 78 * _sy), cost, HORIZONTAL_ALIGNMENT_LEFT, w,
					UI.fit_size(font, cost, Settings.fs("menu", 14), w), cost_col)
