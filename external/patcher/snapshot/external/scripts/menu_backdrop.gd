class_name MenuBackdrop
extends RefCounted
## While a full-screen menu is open (the Ship Computer, a station's window,
## the Field Computer): the world behind it shown as a picture taken as the
## menu opened, the world itself not drawn - the game goes on all the same
## (a hit still closes the menu, which brings the world back). Drawing a whole
## planet or a battle under a menu that hides all but its edges cost a
## quarter to half the frame rate.
##   MenuBackdrop.watch(menu, world)   (world: the scene root under the menu)
## What it hides: the world's own drawn children (culled, not made invisible),
## and its CanvasLayers below the menu's (backgrounds, the HUD). Not headless.

var _rect: TextureRect
var _hidden: Array = []


static func watch(menu: Control, world: Node) -> MenuBackdrop:
	var b := MenuBackdrop.new()
	b._menu = weakref(menu)
	b._world = weakref(world)
	menu.set_meta("menu_backdrop", b)   # (kept as long as the menu is)
	# (a method of its own, not a lambda holding the menu and the world: taken
	# apart with the scene, the menu's last visibility_changed found them freed)
	menu.visibility_changed.connect(b._on_visibility)
	return b


var _menu: WeakRef
var _world: WeakRef

func _on_visibility() -> void:
	var menu: Control = _menu.get_ref() if _menu else null
	var world: Node = _world.get_ref() if _world else null
	if menu == null or world == null or menu.is_queued_for_deletion() or menu.has_meta("prewarm"):
		return   # (gone - or shown for a frame unseen, to draw once: ShipMenu.prewarm)
	set_on(menu, world, menu.visible)


func is_on() -> bool:
	return _rect != null


## The world's drawn children are put on HIDDEN_LAYER (their visibility
## layer) and the viewport stops drawing that layer: hidden without being
## made invisible - showing a planet again after `visible = false` redrew every
## piece of scenery and rebuilt the ground's tiles (a 150 ms frame).
const HIDDEN_LAYER := 1 << 19

func set_on(menu: Control, world: Node, on: bool) -> void:
	if (on and _rect != null) or not menu.is_inside_tree() or not is_instance_valid(world):
		return
	var vp := menu.get_viewport()
	if not on:
		_token = 0   # (a picture still coming: not wanted now)
		if _rect == null:
			return
		_rect.queue_free()
		_rect = null
		for e in _hidden:
			if is_instance_valid(e[0]):
				if e[0] is CanvasLayer:
					e[0].visible = true
				else:
					e[0].visibility_layer = e[1]
		_hidden = []
		vp.canvas_cull_mask = vp.canvas_cull_mask | HIDDEN_LAYER
		return
	if DisplayServer.get_name() == "headless" or _capturing:
		return
	# The picture read back from the GPU without waiting for it (a plain
	# read stalls the frame ~13 ms): it arrives a frame or two later - the
	# world keeps drawing under the menu until then.
	var rd := RenderingServer.get_rendering_device()
	var tex := vp.get_texture()
	var rid := RenderingServer.texture_get_rd_texture(tex.get_rid()) if rd else RID()
	var tf: RDTextureFormat = rd.texture_get_format(rid) if rid.is_valid() else null
	var fmt: int = tf.format if tf else -1
	# (The size of the texture the pixels are read from - not the viewport's:
	# just after the window is resized the two differ, and the picture's bytes
	# didn't match its size: "Expected Image data size of 1916x1079 ... got 1918x1080's".)
	var w: int = tf.width if tf else tex.get_width()
	var h: int = tf.height if tf else tex.get_height()
	if fmt in [RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB]:
		_capturing = true
		var token := Time.get_ticks_usec()
		_token = token
		# (weak references: the picture can arrive after the scene is gone)
		var wm: WeakRef = weakref(menu)
		var ww: WeakRef = weakref(world)
		rd.texture_get_data_async(rid, 0, func(data: PackedByteArray):
			_capturing = false
			var m: Control = wm.get_ref()
			var wo: Node = ww.get_ref()
			if token != _token or _rect != null or m == null or not m.visible or wo == null:
				return   # (closed meanwhile)
			if data.size() != w * h * 4:
				return   # (not the size it was asked at: the world goes on drawing under the menu)
			_show(m, wo, m.get_viewport(), Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)))
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return
	_show(menu, world, vp, img)


var _capturing := false
var _token := 0

func _show(menu: Control, world: Node, vp: Viewport, img: Image) -> void:
	_rect = TextureRect.new()
	_rect.texture = ImageTexture.create_from_image(img)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var holder := menu.get_parent()
	holder.add_child(_rect)
	holder.move_child(_rect, 0)   # (under the menu)
	var layer := _layer_of(menu)
	for c in world.get_children():
		if c is CanvasItem and c.visible and not c.is_ancestor_of(menu):
			_hidden.append([c, c.visibility_layer])
			c.visibility_layer = HIDDEN_LAYER
		elif c is CanvasLayer and c.visible and not c.is_ancestor_of(menu) and c.layer < layer:
			# (backgrounds and the HUD below the menu: hidden - space's starfield is no small thing to draw)
			_hidden.append([c, 0])
			c.visible = false
	vp.canvas_cull_mask = vp.canvas_cull_mask & ~HIDDEN_LAYER


static func _layer_of(n: Node) -> int:
	while n:
		if n is CanvasLayer:
			return n.layer
		n = n.get_parent()
	return 0
