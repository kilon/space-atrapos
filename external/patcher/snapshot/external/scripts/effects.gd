class_name Effects
## One-shot visual effects (explosions, impact sparks), spawned in the FX layer.

static var _glow: Texture2D
static var _additive: CanvasItemMaterial


## An explosion's flash, fire and shockwave; heard as `sound` (Sfx key), or
## by default a big / small boom by size. Ships use ship_sound().
static func explosion(at: Vector2, size := 1.0, sound := "") -> void:
	var p := _particles(int(48 * size), 0.9, 60.0 * size, 280.0 * size, 3.0 * size, 7.0 * size)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 0.85, 1.0))
	g.set_color(1, Color(0.6, 0.05, 0.0, 0.0))
	g.add_point(0.25, Color(1.0, 0.7, 0.2, 1.0))
	g.add_point(0.6, Color(0.9, 0.25, 0.05, 0.7))
	p.color_ramp = g
	_spawn(p, at)
	_spawn(Shockwave.new(size), at)
	if sound == "":
		sound = "space/boom_big" if size >= 0.8 else "space/boom_small"
	Sfx.play_world(sound, at, -2.0 if sound == "space/boom_small" else 0.0, 0.05)


## The sound of a ship blowing up, by how tough it was (hull + shields):
## fighters and interceptors small, gunships and freighters medium, frigates,
## capital ships and bosses large (tools/sfx_space.py ship_boom_*).
static func ship_sound(toughness: float) -> String:
	if toughness < 160.0:
		return "space/ship_boom_small"
	if toughness < 290.0:
		return "space/ship_boom_medium"
	return "space/ship_boom_large"


static func spark(at: Vector2, color: Color) -> void:
	Sfx.play_world("space/spark", at)
	var p := _particles(10, 0.35, 40.0, 180.0, 1.5, 3.0)
	var g := Gradient.new()
	g.set_color(0, color.lightened(0.6))
	g.set_color(1, Color(color, 0.0))
	p.color_ramp = g
	_spawn(p, at)


## Grey rock fragments (asteroid hits and break-ups).
static func debris(at: Vector2, color: Color, size := 1.0) -> void:
	var p := _particles(int(10 + 30 * size), 0.8, 40.0 * size, 220.0 * size, 2.0, 4.5 + size)
	p.material = null  # solid chunks, not glowing
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.darkened(0.4), 0.0))
	p.color_ramp = g
	_spawn(p, at)


## Text that floats up and fades (e.g. "+25 Credits").
static func float_text(at: Vector2, text: String, color := Color.WHITE) -> void:
	_spawn(FloatText.new(text, color), at)


static func _particles(amount: int, lifetime: float, vmin: float, vmax: float,
		smin: float, smax: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.damping_min = vmax * 0.6
	p.damping_max = vmax * 1.0
	p.scale_amount_min = smin * 0.15
	p.scale_amount_max = smax * 0.15
	p.texture = _glow_texture()
	p.material = _additive_material()
	p.finished.connect(p.queue_free)
	p.emitting = true
	return p


## Draws an explosion's particles, a shockwave and a wreck once, unseen, at
## `at` (on the screen: what's off it isn't drawn) - their shaders are made
## then, not in the frame the first ship of a fight blows up (~20 ms).
static func warm(at: Vector2) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var layer := tree.get_first_node_in_group("fx_layer")
	if layer == null:
		return
	var host := Node2D.new()
	host.modulate = Color(1, 1, 1, 0.004)
	layer.add_child(host)
	host.global_position = at
	var p := _particles(4, 0.2, 1.0, 2.0, 1.0, 2.0)
	host.add_child(p)
	host.add_child(Shockwave.new(0.2))
	Wreck.warm(host)
	tree.create_timer(0.3).timeout.connect(host.queue_free)


static func _spawn(node: Node2D, at: Vector2) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var layer := tree.get_first_node_in_group("fx_layer")
	if layer == null:
		node.free()
		return
	layer.add_child(node)
	node.global_position = at


static func _glow_texture() -> Texture2D:
	if _glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 32
		t.height = 32
		_glow = t
	return _glow


static func _additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


class FloatText extends Node2D:
	var text := ""
	var color := Color.WHITE
	var t := 0.0

	func _init(s: String, c: Color) -> void:
		text = s
		color = c
		z_index = 10

	func _process(delta: float) -> void:
		t += delta / 1.4
		position.y -= 40.0 * delta
		if t >= 1.0:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var a := clampf((1.0 - t) * 2.0, 0.0, 1.0)
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(-150, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 300, Settings.fs("world", 18), 5, Color(0, 0, 0, 0.8 * a))
		draw_string(font, Vector2(-150, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 300, Settings.fs("world", 18), Color(color, a))


## Expanding ring + flash.
class Shockwave extends Node2D:
	var size := 1.0
	var t := 0.0

	func _init(s: float) -> void:
		size = s

	func _process(delta: float) -> void:
		t += delta / 0.45
		if t >= 1.0:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var a := 1.0 - t
		draw_circle(Vector2.ZERO, 40.0 * size * (1.0 - t), Color(1, 0.9, 0.6, a * 0.5))
		draw_arc(Vector2.ZERO, 20.0 * size + 90.0 * size * t, 0, TAU, 40,
				Color(1, 0.7, 0.3, a), 3.0 * size, true)
