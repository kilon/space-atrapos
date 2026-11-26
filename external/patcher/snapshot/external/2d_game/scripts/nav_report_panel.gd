class_name NavReportPanel
extends PanelContainer
## A navigation report on screen (NavReports): the system's stations and jump
## gates, its planets and moons, the traffic (hostile ships by who they are,
## friendly and neutral ones by empire and by trade, monsters) and what else is
## there (asteroids, wrecks, signals); under it, what the copy in your hold
## sells for. Opened when the nav beacon's scan is done (Main.chart_with_beacon)
## and by right-clicking a scanned beacon again; ✕ or Esc closes it. The game
## goes on behind it.

var report: Dictionary = {}
## A copy put in the hold now (else: this visit's copy was already given).
var given := true


static func open(parent: Node, r: Dictionary, given_now: bool) -> NavReportPanel:
	for old in parent.get_tree().get_nodes_in_group("nav_report_panel"):
		old.queue_free()
	var p := NavReportPanel.new()
	p.report = r
	p.given = given_now
	parent.add_child(p)
	return p


func _ready() -> void:
	add_to_group("nav_report_panel")
	mouse_filter = MOUSE_FILTER_STOP
	var style := NeonTheme.box(Color(0.45, 1.0, 0.7, 0.75), NeonTheme.BG, 2, 10, 14)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	add_theme_stylebox_override("panel", style)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(UI.label("NAVIGATION REPORT  ·  %s SYSTEM" % str(report.get("name", "")).to_upper(), 22, Color(0.45, 1.0, 0.7)))
	titles.add_child(UI.label("Held by: %s   ·   scanned at its beacon %s" % [report.get("owner", ""), str(report.get("made", "")).replace("T", " ")], 14, UI.TEXT_DIM))
	var close := EditorIcons.dress(UI.button("", close_panel, 14), "close", EditorIcons.tip("Close the report", "Esc", "The copy in your hold keeps it (hover it for a summary)."), "Close")
	head.add_child(close)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	v.add_child(cols)
	# Stations and gates.
	var c1 := _column(cols)
	_section(c1, "STATIONS", report.get("stations", []).size())
	for s in report.get("stations", []):
		_row(c1, "%s  -  %s" % [s[0], s[1]], NeonTheme.TEXT)
	if report.get("stations", []).is_empty():
		_row(c1, "none", UI.TEXT_DIM)
	_section(c1, "JUMP GATES", report.get("gates", []).size())
	for g in report.get("gates", []):
		_row(c1, "to %s" % g, NeonTheme.TEXT)
	# Planets and moons.
	var c2 := _column(cols)
	_section(c2, "PLANETS AND MOONS", report.get("bodies", []).size())
	for b in report.get("bodies", []):
		var line := str(b[0]) + ("  (moon of %s)" % b[3] if str(b[3]) != "" else "")
		if str(b[1]) != "":
			line += "  -  " + str(b[1]).to_lower()
		_row(c2, line + ("  ·  landable" if b[2] else ""), Color(0.6, 1.0, 0.7) if b[2] else NeonTheme.TEXT)
	# Traffic and the rest.
	var c3 := _column(cols)
	var hostile: Dictionary = report.get("hostile", {})
	var friendly: Dictionary = report.get("friendly", {})
	_section(c3, "HOSTILE SHIPS", NavReports.total(hostile))
	for who in hostile:
		_row(c3, "%s: %d" % [who, hostile[who]], Color(1.0, 0.5, 0.42))
	_section(c3, "FRIENDLY AND NEUTRAL SHIPS", NavReports.total(friendly))
	for who in friendly:
		_row(c3, "%s: %d" % [who, friendly[who]], Color(0.55, 0.85, 1.0))
	var roles: Dictionary = report.get("roles", {})
	if not roles.is_empty():
		var parts := PackedStringArray()
		for r in roles:
			parts.append("%s %d" % [_role_name(str(r)), roles[r]])
		_row(c3, "By trade: " + ", ".join(parts), UI.TEXT_DIM)
	var mons: Array = report.get("monsters", [])
	if not mons.is_empty():
		_section(c3, "MONSTERS", mons.size())
		for m in mons:
			_row(c3, str(m), Color(1.0, 0.45, 0.85))
	_section(c3, "ALSO", -1)
	_row(c3, "%d asteroids  ·  %d wrecks  ·  %d signals" % [int(report.get("rocks", 0)), int(report.get("wrecks", 0)), int(report.get("signals", 0))], NeonTheme.TEXT)
	# What the copy sells for.
	var sys := str(report.get("sys", ""))
	var near := PackedStringArray()
	for j in [1, 2, 4]:
		near.append("%d %s away: %d dr" % [j, "jump" if j == 1 else "jumps", NavReports.BASE + NavReports.PER_JUMP * j + NavReports.PER_STATION * report.get("stations", []).size()])
	var foot := ("A copy is in your hold: sell it at a station in another system - the further, the more it pays (%s; nothing here)." % ", ".join(near)) if given \
		else "You've had this visit's copy - leave the system and come back for another (the report above is up to date)."
	v.add_child(UI.note(foot, 14, 1100.0, Color(1.0, 0.82, 0.4)))
	UI.scale_fonts(self, "menu")
	# Centred, on top.
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	(func():
		position = (get_viewport_rect().size - size) / 2.0).call_deferred()


func _column(cols: HBoxContainer) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 2)
	c.custom_minimum_size.x = 300
	cols.add_child(c)
	return c


func _section(c: VBoxContainer, text: String, n: int) -> void:
	if c.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 8
		c.add_child(gap)
	c.add_child(UI.label(text + ("  (%d)" % n if n >= 0 else ""), 15, NeonTheme.HEAD))


func _row(c: VBoxContainer, text: String, col: Color) -> void:
	var l := UI.label(text, 14, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	c.add_child(l)


static func _role_name(r: String) -> String:
	return {"trader": "traders", "miner": "miners", "explorer": "explorers", "patrol": "patrols", "pirate": "pirates",
		"warship": "warships", "fleet": "fleet ships"}.get(r, r + "s")


func close_panel() -> void:
	queue_free()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()
