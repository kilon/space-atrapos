class_name Map3DView
extends Control
## A 3D map in a page of the Automaton (the solar map, the galaxy map -
## each a subclass): its own little 3D world in a SubViewport (MapKit's
## parts), seen by a camera that orbits a focus point, and drawn here as a
## picture with the markers and names over it (projected from 3D).
##
## Mouse: drag to rotate, right / middle drag (or Shift + drag) to pan, the
## wheel zooms toward the cursor, a click selects (pick), a double click
## flies to what's under it, a middle click fits everything (fit()).
## Keys / pad (while its page shows): WASD / arrows / D-pad / left stick
## rotate, the right stick pans, + / - / PageUp / PageDown / the triggers
## zoom, Home fits, Enter / Space / A plot a course to the selection
## (accept()), Backspace / X selects the next thing (cycle()).
## The camera eases to where it's sent. The 3D picture is drawn again when the
## view moves or what it shows changes (both at the screen's rate: frame_hz),
## else `anim_hz` a second (its lines flow, its rings pulse); the overlay
## (markers, names: the costly part, drawn by script) with it while the view
## moves, else `overlay_hz` a second.

signal selected(key: String)

const BG := Color(0.012, 0.012, 0.022)

var vp: SubViewport
var cam: Camera3D
var world: Node3D               # what the subclass shows (its 3D parts)
var focus := Vector3.ZERO
var yaw := 0.7
var pitch := -0.62              # (radians: negative looks down)
var dist := 300.0
var min_dist := 1.0
var max_dist := 20000.0
var anim_hz := 30.0             # (the 3D picture while the view rests: the lines' flow, the rings' pulse)
var overlay_hz := 8.0           # (the markers and names over it while it rests)
var selected_key := ""
var hover_key := ""
## The things on the map that can be picked: key -> {pos (Vector3), r (px)}
## - the subclass fills it (and the overlay draws them).
var marks := {}

var _focus_t := Vector3.ZERO
var _yaw_t := 0.7
var _pitch_t := -0.62
var _dist_t := 300.0
var _dirty := true
var _press := Vector2.ZERO
var _drag := ""                 # "", "rotate", "pan"
var _moved := false
var _drawn_at := 0              # (when the overlay was last drawn, usec)
var _overlay_due := false
var _screen := {}               # key -> where it is on the screen (this picture)
var _behind := {}               # key -> true: behind the camera


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.size = Vector2i(64, 64)
	vp.positional_shadow_atlas_size = 0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 200000.0
	vp.add_child(cam)
	world = Node3D.new()
	vp.add_child(world)
	add_child(vp)


## Sends the camera (eased) to look at `at` from `d` away (keeping its turn).
func fly_to(at: Vector3, d := -1.0) -> void:
	_focus_t = at
	if d > 0.0:
		_dist_t = clampf(d, min_dist, max_dist)


## The camera where it was being sent, at once (no easing).
func snap() -> void:
	focus = _focus_t
	yaw = _yaw_t
	pitch = _pitch_t
	dist = _dist_t
	_dirty = true


static var _hz := 0.0

## The screen's frames a second (60-240): how often a map that moves is drawn.
static func frame_hz() -> float:
	if _hz <= 0.0:
		var r := DisplayServer.screen_get_refresh_rate() if DisplayServer.get_name() != "headless" else -1.0
		_hz = clampf(r if r > 1.0 else 60.0, 60.0, 240.0)
	return _hz


## Puts the camera there at once (no easing).
func snap_to(at: Vector3, d: float) -> void:
	_focus_t = at
	focus = at
	_dist_t = clampf(d, min_dist, max_dist)
	dist = _dist_t
	_dirty = true


## Shows the box round `pts` (eased; `now`: at once).
func fit_points(pts: Array, now := false) -> void:
	if pts.is_empty():
		return
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	var r := maxf(box.size.length() * 0.5, min_dist * 2.0)
	var d := r / tan(deg_to_rad(cam.fov) * 0.5) * 0.85
	if size.x > 1.0 and size.y > 1.0 and size.x < size.y:
		d *= size.y / size.x
	if now:
		snap_to(box.get_center(), d)
	else:
		fly_to(box.get_center(), d)


## (The subclass: what fit() shows - everything known.)
func fit(now := false) -> void:
	pass


## Something in it changed: drawn again next frame.
func mark_dirty() -> void:
	_dirty = true


## The overlay drawn again at the next rest tick (what it shows moved).
func overlay_due() -> void:
	_overlay_due = true


# --- Each frame ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_controls(delta)
	var k := 1.0 - exp(-delta * 10.0)
	var moving := focus.distance_to(_focus_t) > dist * 0.0005 or absf(yaw - _yaw_t) > 0.0005 or absf(pitch - _pitch_t) > 0.0005 \
		or absf(dist - _dist_t) > dist * 0.0005
	if moving:
		focus = focus.lerp(_focus_t, k)
		yaw = lerpf(yaw, _yaw_t, k)
		pitch = lerpf(pitch, _pitch_t, k)
		dist = exp(lerpf(log(dist), log(_dist_t), k))
	_place_camera()
	var sz := Vector2i(maxi(8, int(size.x)), maxi(8, int(size.y)))
	if vp.size != sz:
		vp.size = sz
		_dirty = true
	var now := Time.get_ticks_usec()
	if moving or _dirty:
		_dirty = false
		_view_changed()
		# (The picture and the overlay together, as often as the screen shows
		# frames: the markers never lag the picture - and no 3D picture made 600
		# times a second that the screen shows 144 of.)
		if now - _drawn_at >= int(1e6 / frame_hz()) - 500:
			_drawn_at = now
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			queue_redraw()
		else:
			_dirty = true   # (drawn at the next screen frame)
	elif UI.redraw_due(self, anim_hz):
		tick()
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE   # (the picture: its shaders' motion)
		if now - _drawn_at > int(1e6 / overlay_hz) or _overlay_due:
			_overlay_due = false
			_drawn_at = now
			queue_redraw()


func _place_camera() -> void:
	var dir := Vector3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw))
	cam.position = focus + dir * dist
	cam.near = maxf(dist * 0.002, 0.01)
	cam.far = maxf(dist * 60.0, 1000.0)
	cam.look_at(focus, Vector3.UP if absf(pitch) < 1.55 else Vector3.FORWARD)


## (The subclass: the camera moved - sizes kept on the screen follow.)
func _view_changed() -> void:
	pass


## (The subclass: `anim_hz` a second while the view rests - what moves.)
func tick() -> void:
	pass


# --- Drawing -------------------------------------------------------------------------

func _draw() -> void:
	draw_texture_rect(vp.get_texture(), Rect2(Vector2.ZERO, size), false)
	_screen = {}
	_behind = {}
	for key in marks:
		var p: Vector3 = marks[key]["pos"]
		if cam.is_position_behind(p):
			_behind[key] = true
			continue
		_screen[key] = cam.unproject_position(p)
	draw_overlay()


## (The subclass: the markers and names, over the picture - at_screen() for each.)
func draw_overlay() -> void:
	pass


## Where a mark is on the screen (null: behind the camera).
func at_screen(key: String) -> Variant:
	return _screen.get(key)


## Where a point is on the screen (null: behind the camera).
func project(p: Vector3) -> Variant:
	return null if cam.is_position_behind(p) else cam.unproject_position(p)


## The mark under the cursor ("": none).
func pick(at: Vector2) -> String:
	var best := ""
	var bd := INF
	for key in _screen:
		var r := maxf(float(marks[key].get("r", 12.0)), 12.0)
		var d: float = (_screen[key] as Vector2).distance_to(at)
		if d < r and d < bd:
			bd = d
			best = key
	return best


static var _widths := {}        # (names' widths, measured once)

## A name tag drawn where it doesn't cover another (`taken`: the tags so far).
func tag(at: Vector2, text: String, fs: int, col: Color, taken: Array, font: Font = null, centred := true) -> bool:
	if font == null:
		font = NeonTheme.heavy_font()
	var wk := "%d|%s" % [fs, text]
	var w: float = _widths.get(wk, -1.0)
	if w < 0.0:
		w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if _widths.size() > 2000:
			_widths.clear()
		_widths[wk] = w
	var r := Rect2(at - Vector2(w * 0.5 if centred else 0.0, fs), Vector2(w, fs * 1.2))
	var pad := r.grow_individual(8.0, 2.0, 8.0, 2.0)
	for t: Rect2 in taken:
		if t.intersects(pad):
			return false
	taken.append(r)
	draw_string_outline(font, r.position + Vector2(0, fs), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
	draw_string(font, r.position + Vector2(0, fs), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return true


# --- Input ----------------------------------------------------------------------------

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom(0.85 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.85, mb.position)
		elif UI.middle_click(self, mb):
			fit()
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_press = mb.position
				_moved = false
				_drag = "rotate" if mb.button_index == MOUSE_BUTTON_LEFT else "pan"
				if mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
					var k := pick(mb.position)
					if k != "":
						fly_to(marks[k]["pos"], _dist_t * 0.45)
						clicked(k, false)
					_drag = ""
			else:
				if not _moved and mb.button_index == MOUSE_BUTTON_LEFT and _drag != "":
					clicked(pick(mb.position), mb.shift_pressed)
				elif not _moved and mb.button_index == MOUSE_BUTTON_RIGHT and _drag != "":
					right_clicked(pick(mb.position))
				_drag = ""
		accept_event()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _drag != "" and (mm.position.distance_to(_press) > 4.0 or _moved):
			_moved = true
			if _drag == "rotate" and not mm.shift_pressed:
				_yaw_t -= mm.relative.x * 0.008
				_pitch_t = clampf(_pitch_t - mm.relative.y * 0.006, -1.5, 1.5)
			else:
				pan(mm.relative)
		else:
			var h := pick(mm.position)
			if h != hover_key:
				hover_key = h
				queue_redraw()
		accept_event()


## Zoom by `f` (under 1: in) toward the screen point `at`.
func zoom(f: float, at := Vector2(-1, -1)) -> void:
	var nd := clampf(_dist_t * f, min_dist, max_dist)
	f = nd / _dist_t
	if at.x >= 0.0 and f < 1.0:
		var p := cam.project_position(at, dist)
		_focus_t += (p - _focus_t) * (1.0 - f) * 0.9
	_dist_t = nd


## Pans by a screen motion (px).
func pan(rel: Vector2) -> void:
	var k := 2.0 * _dist_t * tan(deg_to_rad(cam.fov) * 0.5) / maxf(size.y, 1.0)
	var right := cam.global_basis.x
	var up := cam.global_basis.y
	_focus_t += (-right * rel.x + up * rel.y) * k


## (The subclass: a click on `key` ("": empty space); Shift held: `add`.)
func clicked(key: String, _add: bool) -> void:
	if key != "":
		select(key)


## (The subclass: a right click.)
func right_clicked(_key: String) -> void:
	pass


func select(key: String) -> void:
	selected_key = key
	_dirty = true
	selected.emit(key)


## (The subclass: Enter / A - plot a course to the selection.)
func accept() -> void:
	pass


## The next mark after the selection (Backspace / X): in the order of
## cycle_order() (the subclass's), nearest first.
func cycle(d := 1) -> void:
	var keys := cycle_order()
	if keys.is_empty():
		return
	var i := keys.find(selected_key)
	var k: String = keys[wrapi(i + d, 0, keys.size())] if i >= 0 else keys[0]
	select(k)
	fly_to(marks[k]["pos"])


func cycle_order() -> Array:
	return marks.keys()


## Is this map the one the keys and the pad drive (its page on top)?
func _driving() -> bool:
	if not is_visible_in_tree() or UI.esc_menu_open():
		return false
	var m := Keybinds.active_menu()
	if m != null and not m.is_ancestor_of(self):
		return false
	var f := get_viewport().gui_get_focus_owner()
	return not (f is LineEdit or f is TextEdit)


func _input(ev: InputEvent) -> void:
	if not _driving():
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed:
		match (ev as InputEventKey).keycode:
			KEY_HOME:
				fit()
				get_viewport().set_input_as_handled()
				return
	for a in ["menu_up", "menu_down", "menu_left", "menu_right"]:
		if Keybinds.pressed_repeat(ev, a):
			get_viewport().set_input_as_handled()   # (they turn the map - not the focus round the page)
			return
	if Keybinds.pressed(ev, "menu_accept"):
		accept()
		get_viewport().set_input_as_handled()
	elif Keybinds.pressed(ev, "menu_secondary"):
		cycle()
		get_viewport().set_input_as_handled()


## The held keys and the pad's sticks, each frame.
func _controls(delta: float) -> void:
	if not _driving():
		return
	var turn := Vector2(Input.get_action_strength("menu_right") - Input.get_action_strength("menu_left"),
		Input.get_action_strength("menu_down") - Input.get_action_strength("menu_up"))
	var pan_v := Vector2.ZERO
	var z := 0.0
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD) or Input.is_key_pressed(KEY_PAGEUP):
		z -= 1.0
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT) or Input.is_key_pressed(KEY_PAGEDOWN):
		z += 1.0
	for dev in Input.get_connected_joypads():
		var ls := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		if ls.length() > Keybinds.DEADZONE:
			turn += ls
		var rs := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
		if rs.length() > Keybinds.DEADZONE:
			pan_v += rs
		z += Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT) - Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT)
	if turn != Vector2.ZERO:
		_yaw_t -= turn.x * delta * 1.8
		_pitch_t = clampf(_pitch_t + turn.y * delta * 1.3, -1.5, 1.5)
	if pan_v != Vector2.ZERO:
		pan(-pan_v * delta * 600.0)
	if absf(z) > 0.1:
		_dist_t = clampf(_dist_t * exp(z * delta * 1.6), min_dist, max_dist)
