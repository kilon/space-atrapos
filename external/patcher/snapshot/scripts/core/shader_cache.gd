class_name ShaderCache
extends Control
## A shader-drawn backdrop (a planet, a nebula) drawn into a picture a few
## times a second instead of every frame: their noise shaders (several 3D
## noise fields a pixel) were half of a space frame's GPU time, and what they
## show - a slow turn, a slow drift - doesn't need 600 pictures a second.
## The source (a ColorRect with its ShaderMaterial) is moved (a frame or a few
## later: _build, one a frame) into an off-screen viewport (at most max_px across); a TextureRect shows that
## viewport's picture where the source was, drawn with the source's blend
## (premultiplied for planets, additive for nebulae). The picture is renewed
## `hz` times a second while it's on screen; off screen not at all.
##   holder.add_child(ShaderCache.wrap(rect, 12.0))      (rect: positioned and sized already)

var hz := 10.0
var _vp: SubViewport
var _t := 0.0
var _src: Control
var _max_px := 1024.0
var _blend := CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
## One cache is set up a frame (a viewport each: ~6 ms; a system's planets and
## nebulae all at once were 70 ms of its first frame) - till then the source
## draws itself, live.
static var _turn := -1


static func wrap(src: Control, hz_ := 10.0, max_px := 1024.0, blend := CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA) -> ShaderCache:
	var c := ShaderCache.new()
	c.hz = hz_
	c.name = "ShaderCache"
	c.position = src.position
	c.size = src.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# (Like the shader it stands for, it runs whatever the game does - paused,
	# or a scene still being built a piece a frame: its picture is ready by
	# the time the scene shows.)
	c.process_mode = Node.PROCESS_MODE_ALWAYS
	c._src = src
	c._max_px = max_px
	c._blend = blend
	src.position = Vector2.ZERO
	c.add_child(src)
	return c


## Moves the source into its viewport and shows the viewport's picture in its place.
func _build() -> void:
	var src := _src
	var k := minf(1.0, _max_px / maxf(maxf(src.size.x, src.size.y), 1.0))
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.size = Vector2i(maxi(1, ceili(src.size.x * k)), maxi(1, ceili(src.size.y * k)))
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	remove_child(src)
	src.scale = Vector2(k, k)
	_vp.add_child(src)
	add_child(_vp)
	var view := TextureRect.new()
	view.name = "Picture"
	view.texture = _vp.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.size = size
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := CanvasItemMaterial.new()
	m.blend_mode = _blend
	view.material = m
	add_child(view)


func _process(delta: float) -> void:
	if _vp == null:
		if not is_instance_valid(_src):
			return   # (its scene being taken apart, the leaves first)
		var f := Engine.get_process_frames()
		if f != _turn:
			_turn = f
			_build()
		return
	if not is_instance_valid(_vp):
		return
	_t -= delta
	if _t > 0.0:
		return
	if not _on_screen():
		_t = 0.2   # (looked at again soon: it may come into view)
		return
	_t = 1.0 / hz
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _on_screen() -> bool:
	if not is_visible_in_tree():
		return false
	var r := get_global_transform_with_canvas() * Rect2(Vector2.ZERO, size)
	return get_viewport_rect().grow(64.0).intersects(r)
