extends TextureRect
## An item's picture in its tooltip (PinTips): the thing itself in a small lit world of its own, turning
## slowly - drawn at the screen's own pixels (however big the interface is scaled), so it's never blurred.
## `source` (Callable -> a Mesh or a Node3D to copy, or null while it isn't ready - asked again each frame
## till it is); `fallback`: a picture shown meanwhile.

const TURN := 5.0   # seconds a turn

var source := Callable()
var fallback: Texture2D
var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _model: Node3D


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture = fallback
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = _pixels()
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.6
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.7, 0.8, 1.0)
	_vp.add_child(rim)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)


## The picture's size in the screen's pixels (the interface scaled up on a big screen: as many more).
func _pixels() -> Vector2i:
	var s := 1.0
	if is_inside_tree():
		var w := get_tree().root
		s = w.content_scale_factor
		if w.content_scale_size.y > 0 and w.content_scale_mode != Window.CONTENT_SCALE_MODE_DISABLED:
			s *= float(w.size.y) / float(w.content_scale_size.y)
		s = maxf(s, 1.0)
	var want := custom_minimum_size if custom_minimum_size != Vector2.ZERO else size
	return Vector2i(maxi(16, ceili(want.x * s)), maxi(16, ceili(want.y * s)))


func _process(dt: float) -> void:
	if _vp == null:
		return
	var px := _pixels()
	if px != _vp.size:
		_vp.size = px
	if _model == null and source.is_valid():
		var n = source.call()
		if n is Mesh:
			var mi := MeshInstance3D.new()
			mi.mesh = n
			_put(mi)
		elif n is Node3D:
			_put((n as Node3D).duplicate())
	if _model != null:
		_pivot.rotation.y += dt * TAU / TURN


func _put(n: Node3D) -> void:
	_model = n
	_pivot.add_child(n)
	_aim()
	texture = _vp.get_texture()


func _aim() -> void:
	var box := AABB()
	var first := true
	for v in _model.find_children("*", "VisualInstance3D", true, false) + ([_model] if _model is VisualInstance3D else []):
		var vi := v as VisualInstance3D
		var b: AABB = vi.global_transform * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var c := box.get_center()
	_model.position -= Vector3(c.x, 0, c.z)   # (turning about its own middle)
	var r := maxf(Vector2(box.size.x, box.size.z).length() * 0.5, box.size.y * 0.5)
	r = maxf(Vector3(r, box.size.y * 0.5, r).length() * 0.62, 0.05)   # (filling its box - turning, it stays inside)
	var dir := Vector3(0.0, 0.32, 1.0).normalized()
	var dist := r / sin(deg_to_rad(_cam.fov * 0.5)) * 1.02
	var look := Vector3(0, c.y, 0)
	_cam.look_at_from_position(look + dir * dist, look, Vector3.UP)
	_cam.near = maxf(dist * 0.01, 0.001)
	_cam.far = dist * 4.0
