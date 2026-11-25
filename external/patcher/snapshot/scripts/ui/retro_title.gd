class_name RetroTitle
extends Control
## The 80s game title: "SPACE" in spaced-out neon letters over a huge,
## slanted, heavy "ATRAPOS" with a chrome blue-to-red gradient, a dark
## outline and a pulsing pink / violet neon glow.

@export var big_size := 150
@export var small_size := 44
@export var top_text := "SPACE"
@export var main_text := "ATRAPOS"

var _small_font: FontVariation
var _fill: Control
var _t := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_small_font = FontVariation.new()
	_small_font.base_font = NeonTheme.title_font()
	_small_font.spacing_glyph = int(small_size * 0.55)
	var f := NeonTheme.title_font()
	var main_w := f.get_string_size(main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big_size).x
	custom_minimum_size = Vector2(main_w + big_size * 0.6, small_size * 1.4 + big_size * 1.15)
	# The gradient letters are a child, so the glow (drawn here) sits behind them.
	_fill = Control.new()
	_fill.mouse_filter = MOUSE_FILTER_IGNORE
	_fill.set_anchors_preset(PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/chrome_text.gdshader")
	_fill.material = mat
	_fill.draw.connect(_draw_fill)
	add_child(_fill)
	resized.connect(_update_shader)
	_update_shader()


func _process(delta: float) -> void:
	_t += delta
	if is_visible_in_tree():   # (the Esc menu's title: hidden most of the game)
		queue_redraw()


## Baseline position of the main word.
func _main_pos() -> Vector2:
	var f := NeonTheme.title_font()
	var w := f.get_string_size(main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big_size).x
	return Vector2((size.x - w) / 2.0 - big_size * 0.08, small_size * 1.4 + f.get_ascent(big_size) * 0.92)


func _update_shader() -> void:
	var f := NeonTheme.title_font()
	var p := _main_pos()
	var mat := _fill.material as ShaderMaterial
	mat.set_shader_parameter("top", p.y - f.get_ascent(big_size) * 0.78)
	mat.set_shader_parameter("bottom", p.y + f.get_descent(big_size) * 0.1)
	mat.set_shader_parameter("width", maxf(size.x, 1.0))
	_fill.queue_redraw()


func _draw() -> void:
	var f := NeonTheme.title_font()
	var p := _main_pos()
	var pulse := 0.85 + 0.15 * sin(_t * 2.2)
	# Layered neon glow behind the letters.
	for g in [[54, Color(0.55, 0.2, 1.0, 0.06)], [38, Color(1.0, 0.2, 0.7, 0.09)], [24, Color(1.0, 0.25, 0.75, 0.16)], [14, Color(0.35, 0.8, 1.0, 0.25)]]:
		var c: Color = g[1]
		c.a *= pulse
		draw_string_outline(f, p, main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big_size, g[0], c)
	# Dark chrome edge with a thin light rim, plus a drop shadow.
	draw_string(f, p + Vector2(6, 8), main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big_size, Color(0.05, 0.0, 0.12, 0.8))
	draw_string_outline(f, p, main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big_size, 9, Color(0.04, 0.02, 0.14))
	draw_string_outline(f, p, main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big_size, 4, Color(0.85, 0.9, 1.0, 0.9))
	# "SPACE": neon tube letters with lines either side.
	var sw := _small_font.get_string_size(top_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size).x
	var sp := Vector2((size.x - sw) / 2.0 + _small_font.spacing_glyph * 0.5, small_size * 1.05)
	var cyan := Color(0.3, 0.9, 1.0)
	for g in [[22, Color(cyan, 0.08)], [12, Color(cyan, 0.18)], [6, Color(cyan, 0.4)]]:
		var c: Color = g[1]
		c.a *= pulse
		draw_string_outline(_small_font, sp, top_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, g[0], c)
	draw_string_outline(_small_font, sp, top_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, 2, Color(0.6, 1.0, 1.0))
	draw_string(_small_font, sp, top_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, Color(0.92, 1.0, 1.0))
	var ly := sp.y - small_size * 0.35
	for side in [-1, 1]:
		var x0: float = size.x / 2.0 + side * (sw / 2.0 + 24)
		var x1: float = size.x / 2.0 + side * (size.x * 0.45)
		draw_line(Vector2(x0, ly), Vector2(x1, ly), Color(1.0, 0.25, 0.75, 0.25 * pulse), 7.0)
		draw_line(Vector2(x0, ly), Vector2(x1, ly), Color(1.0, 0.55, 0.85), 2.0)
		draw_line(Vector2(x0, ly + 9), Vector2(lerpf(x0, x1, 0.7), ly + 9), Color(0.3, 0.9, 1.0, 0.8), 1.5)


func _draw_fill() -> void:
	_fill.draw_string(NeonTheme.title_font(), _main_pos(), main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, big_size, Color.WHITE)
