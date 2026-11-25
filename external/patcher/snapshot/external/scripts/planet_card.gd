class_name PlanetCard
extends PanelContainer
## The planet card at the bottom right in space, after the reference console's
## sector panel: the planet's name and kind, a picture of it (a slice of the
## planet seen from orbit, lit by its star, over the stars), facts in label /
## value rows, and its description. It shows the planet under the mouse, or
## the one you're close to, and fades away when there's none.

const WIDTH := 340.0
const PICTURE := Vector2(308, 150)
const NEAR := 900.0                 # this far past a planet's edge it still counts as near
const CHECK := 0.2                  # seconds between looks for the planet to show

var main: Node                      # main.gd (its ship and camera)
var body: OrbitBody                 # the planet shown (null: none)
var _title: Label
var _kind: Label
var _picture: Control
var _rows: GridContainer
var _desc: Label
var _t := 0.0


func _ready() -> void:
	name = "PlanetCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0)
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -16
	offset_bottom = -16
	offset_left = -16 - WIDTH   # (it grows up and left to fit its contents)
	offset_top = -16 - 100
	var style := UI.panel_style(NeonTheme.CYAN)
	style.bg_color = Color(NeonTheme.BG, 0.88)
	add_theme_stylebox_override("panel", style)
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 14)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(box)
	_title = UI.label("", 26, NeonTheme.TEXT)
	_title.add_theme_font_override("font", NeonTheme.heavy_font())
	box.add_child(_title)
	_kind = UI.label("", 16, NeonTheme.CYAN)
	_kind.add_theme_font_override("font", load("res://assets/fonts/Rajdhani-SemiBold.ttf"))
	box.add_child(_kind)
	_picture = Control.new()
	_picture.custom_minimum_size = PICTURE
	_picture.clip_contents = true
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.draw.connect(_draw_picture_back)
	box.add_child(_picture)
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 18)
	_rows.add_theme_constant_override("v_separation", 2)
	box.add_child(_rows)
	_desc = UI.label("", 14, NeonTheme.TEXT_DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(PICTURE.x, 0)
	box.add_child(_desc)
	modulate.a = 0.0
	visible = false


func _process(delta: float) -> void:
	if main == null:   # (filled by hand - the planet map): always shown
		modulate.a = 1.0
		visible = true
		return
	_t -= delta
	if _t <= 0.0:
		_t = CHECK
		var b := pick()
		if b != body:
			body = b
			if b:
				_fill(b)
	var want := 1.0 if body != null and is_instance_valid(body) else 0.0
	modulate.a = move_toward(modulate.a, want, delta * 4.0)
	visible = modulate.a > 0.01


## The planet to show: the one under the mouse, else the nearest you're close to.
func pick() -> OrbitBody:
	if main == null or main.get("ship") == null or not main.ship.is_alive() or main.get("site") != null:
		return null
	var mouse: Vector2 = main.get_global_mouse_position()
	var best: OrbitBody = null
	var best_d := INF
	for b in get_tree().get_nodes_in_group("planet_bodies"):
		var r: float = b.radius
		if b.global_position.distance_to(mouse) < r:
			return b
		var d: float = b.global_position.distance_to(main.ship.global_position) - r
		if d < NEAR and d < best_d:
			best_d = d
			best = b
	return best


func _fill(b: OrbitBody) -> void:
	var kind: String = str(b.spec.get("name", "Planet"))
	if b.parent_body:
		kind += "  ·  moon of " + b.parent_body.title
	var moons := 0
	for o in get_tree().get_nodes_in_group("planet_bodies"):
		if o.parent_body == b:
			moons += 1
	var danger: float = Galaxy.pirate_level(Galaxy.current_system)
	var rows := [["SYSTEM", Galaxy.systems.get(Galaxy.current_system, {}).get("name", "-")],
		["ORBIT", "%.1fk" % (b.orbit / 1000.0)],
		["MOONS", str(moons)] if not b.parent_body else ["PARENT", b.parent_body.title],
		["SURFACE", "Landable" if b.landable else "No landing"],
		["THREAT", threat_word(danger)]]
	show_planet(b.title, kind, b.spec, rows, b.desc)


static func threat_word(danger: float) -> String:
	return ["Low", "Medium", "High", "Extreme"][clampi(int(danger * 3.99), 0, 3)]


## Fills the card (also used without a planet in space - the planet map):
## rows are [label, value] pairs; a THREAT of High / Extreme shows orange.
func show_planet(title: String, kind: String, spec: Dictionary, rows: Array, desc: String) -> void:
	_title.text = title.to_upper()
	_kind.text = kind.to_upper()
	# The picture: a big slice of the planet, lit from the upper left.
	for c in _picture.get_children():
		c.queue_free()
	var size := PICTURE.x * 1.5
	var p := Planets.make_planet(spec, size)
	p.position = Vector2(PICTURE.x * 0.5 - size * 0.5 + 40.0, PICTURE.y * 0.42)
	PlanetGen.set_light(p, Vector2(-1.0, -0.7))
	_picture.add_child(p)
	var frame := Control.new()   # (the picture's cyan frame, over the planet)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.draw.connect(func():
		frame.draw_rect(Rect2(Vector2.ONE, frame.size - Vector2.ONE * 2.0), Color(NeonTheme.CYAN, 0.55), false, 1.5)
		frame.draw_line(Vector2(1, 1), Vector2(28, 1), NeonTheme.PINK, 3.0))
	_picture.add_child(frame)
	_picture.queue_redraw()
	UI.clear(_rows)
	for r in rows:
		var k := UI.label(r[0], 15, Color(NeonTheme.CYAN, 0.85))
		k.add_theme_font_override("font", load("res://assets/fonts/Rajdhani-SemiBold.ttf"))
		_rows.add_child(k)
		var hot: bool = r[0] == "THREAT" and str(r[1]) in ["High", "Extreme"]
		var v := UI.label(str(r[1]), 15, NeonTheme.PINK if hot else NeonTheme.TEXT)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_rows.add_child(v)
	_desc.text = desc


## Behind the planet: deep space with a few stars, and a cyan frame on top.
func _draw_picture_back() -> void:
	var r := Rect2(Vector2.ZERO, _picture.size)
	_picture.draw_rect(r, NeonTheme.BG)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(body.title if body else "")
	for i in 40:
		var p := Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y)
		_picture.draw_circle(p, rng.randf_range(0.5, 1.4), Color(0.8, 0.95, 1.0, rng.randf_range(0.3, 0.9)))

