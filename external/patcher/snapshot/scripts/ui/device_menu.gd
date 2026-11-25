class_name DeviceMenu
extends Control
## A device of your ship's own - its REFINERY or its FABRICATOR - in a window of
## its own, opened at its terminal aboard (CosmosShipInterior.TERMINALS; Cosmos.open_device),
## as a station's terminals open one service each. Its work is the ship's
## industry (Industry: the queue goes on while you fly), shown by the
## Industry page restricted to the device: the refinery its refining; the
## fabricator its recipes and fitting Upgrade Kits.

const DEVICES := {
	"refinery": ["REFINERY", [0], "Turns the fragments you've mined into their minerals. It works on while you fly."],
	"fabricator": ["FABRICATOR", [1, 2], "Makes things from minerals and goods - materials, components, spare parts, supplies, weapons, Upgrade Kits - and fits Upgrade Kits."],
}

var data: Node
var kind := ""
var _title: Label
var _page: Control
var _header: Control


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)   # (the whole screen: offsets too - made in code, not a scene)
	Keybinds.register_menu(self)


func _build() -> void:
	var root := UI.modal(self, Color(NeonTheme.TEXT_DIM, 0.9), Vector2.ZERO, true)
	var header := HBoxContainer.new()
	_title = UI.label("", 28, NeonTheme.HEAD)
	header.add_child(_title)
	header.add_child(UI.spacer())
	header.add_child(EditorIcons.dress(UI.button("", close), "close", EditorIcons.tip("Close", "Esc", "Closes the device's window (its work goes on).")))
	root.add_child(header)
	_header = header
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	root.add_child(scroll)
	_page = load("res://scripts/ui/pages/industry_page.gd").new()
	_page.data = data
	_page.size_flags_horizontal = SIZE_EXPAND_FILL
	_page.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.add_child(_page)
	data.changed.connect(func():
		if visible:
			_page.refresh())


## Opens the device `kind` ("refinery", "fabricator").
func open(k: String) -> void:
	if _page == null:
		_build()
	kind = k
	var d: Array = DEVICES.get(k, DEVICES["fabricator"])
	_title.text = d[0]
	_title.tooltip_text = d[2]
	_page.show_only(d[1])
	var was_open := visible and not HexReveal.closing(self)
	show()
	_page.refresh()
	UI.scale_fonts(_page, "menu")
	UI.scale_fonts(_header, "menu", 1.5)
	if not was_open:
		HexReveal.play(self)


func close() -> void:
	if not visible:
		return
	HexReveal.play(self, true, hide)


func _input(event: InputEvent) -> void:
	if not visible or UI.esc_menu_open():
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
