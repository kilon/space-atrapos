class_name IconAnim
extends Control
## An icon button's icon coming alive while the mouse is on it: the same picture drawn
## moving - the turn icon spinning, cubes and shapes turning round like a turntable,
## arrows pushing out, an extrude or a flip bobbing, rings breathing, the rest
## pulsing with a glint. Drawn over the button in the icon's place (the button's own
## icon hidden meanwhile, its size kept), by the clock; eased back to rest when the
## mouse leaves, then the button's icon is back and this sleeps. Nothing repainted:
## one texture, a transform.
##   IconAnim.attach(button, "m_rotate")   (EditorIcons.dress does it for every icon button)

## How each icon moves (by name; prefixes for families): spin, turn, push, bob, breathe,
## swing, pulse (the default).
const KINDS := {
	"m_rotate": "spin", "reload": "spin", "restart": "spin", "m_torus": "spin", "m_falloff": "breathe",
	"m_move": "push", "m_scale": "push", "fit_all": "push", "m_frame": "push", "m_frame_all": "push",
	"m_extrude": "bob", "m_flip": "bob", "m_normals": "bob", "up": "bob", "down": "bob", "land": "bob",
	"m_prop": "breathe", "m_merge": "breathe", "m_connected": "swing", "undo": "swing", "redo": "swing",
	"back": "swing", "forward": "swing", "next": "swing", "exit": "swing",
	"m_mirror_x": "turn", "m_mirror_y": "turn", "m_mirror_z": "turn", "m_symmetrize": "turn", "m_symmetrize_back": "turn",
	"m_box": "turn", "m_cylinder": "turn", "m_cone": "turn", "m_sphere": "turn", "m_plane": "turn",
	"m_object": "turn", "m_edit": "turn", "m_vertex": "turn", "m_edge": "turn", "m_face": "turn",
	"m_front": "turn", "m_side": "turn", "m_top": "turn", "mesh": "turn", "mod": "turn", "ui_cargo": "turn",
	"anim": "swing", "play": "push", "effects": "breathe", "ui_galaxy": "spin", "ui_system": "spin", "patch": "swing",
	"m_union": "breathe", "m_difference": "pulse", "m_intersect": "breathe", "m_slice": "swing", "m_shapes": "turn",
	"m_shape_save": "bob", "m_shape_add": "bob", "m_knife": "swing", "m_ngons": "turn", "m_auto_select": "push", "m_dissolve": "breathe", "m_symmetrize_topo": "turn", "m_bind_auto": "swing", "m_bind_bone": "swing",
	"m_materials": "turn", "m_mat_new": "bob", "m_mat_duplicate": "push", "m_mat_rename": "swing", "m_mat_delete": "swing", "m_mat_assign": "bob",
	"m_move_smart": "bob", "m_move_persp": "push", "m_gizmo": "spin", "m_panel_left": "push", "m_panel_right": "push", "m_maximize": "push", "m_restore": "push", "m_tpose": "swing", "m_weapons": "swing", "save": "bob", "delete": "swing", "duplicate": "push", "add": "spin", "help": "swing", "docs": "swing",
}
const SPEED := 1.6     # cycles a second (spin: turns a second / 2)
const EASE := 7.0      # how quickly it settles back

var button: Button
var tex: Texture2D
var kind := "pulse"
var _t := 0.0
var _amt := 0.0         # 0 at rest .. 1 alive
var _on := false

static var _blank := {}  # size -> a clear texture (the button's icon while this draws it)


static func attach(b: Button, icon_name: String) -> void:
	if b == null or b.has_meta("icon_anim"):
		return
	var a := IconAnim.new()
	a.button = b
	a.kind = KINDS.get(icon_name, "spin" if icon_name.begins_with("m_sym") else "pulse")
	a.name = "IconAnim"
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.set_meta("icon_anim", a)
	b.add_child(a)
	b.mouse_entered.connect(a._start)
	b.mouse_exited.connect(a._stop)


func _ready() -> void:
	set_process(false)


func _start() -> void:
	if button.disabled or button.icon == null:
		return
	if not _on and _amt <= 0.0:
		tex = button.icon
		button.icon = _clear(tex.get_size())
		_t = 0.0
	_on = true
	set_process(true)


func _stop() -> void:
	_on = false


static func _clear(sz: Vector2) -> Texture2D:
	var k := Vector2i(sz)
	if not _blank.has(k):
		var img := Image.create_empty(maxi(k.x, 1), maxi(k.y, 1), false, Image.FORMAT_RGBA8)
		_blank[k] = ImageTexture.create_from_image(img)
	return _blank[k]


func _process(dt: float) -> void:
	if not is_instance_valid(button) or tex == null:
		set_process(false)
		return
	if button.icon != null and not button.icon in _blank.values():
		tex = button.icon   # (the button's code changed its icon meanwhile - Play to Stop: that one moves now)
		button.icon = _clear(tex.get_size())
	_t += dt
	_amt = move_toward(_amt, 1.0 if _on else 0.0, dt * EASE)
	if not _on and _amt <= 0.0:
		button.icon = tex   # (at rest: the button's own icon back)
		tex = null
		set_process(false)
	queue_redraw()


## Where the button draws its icon: centred when it has no text, else at its left.
func _icon_rect() -> Rect2:
	var sz := tex.get_size()
	if button.expand_icon:
		var h := size.y * 0.6
		sz = Vector2(h, h)
	var sb := button.get_theme_stylebox("normal")
	var left := sb.get_margin(SIDE_LEFT) if sb else 4.0
	var x := (size.x - sz.x) * 0.5 if button.text == "" or button.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER else left
	if button.icon_alignment == HORIZONTAL_ALIGNMENT_RIGHT and button.text != "":
		x = size.x - (sb.get_margin(SIDE_RIGHT) if sb else 4.0) - sz.x
	var y := (size.y - sz.y) * 0.5
	if button.vertical_icon_alignment == VERTICAL_ALIGNMENT_TOP and button.text != "":
		y = (sb.get_margin(SIDE_TOP) if sb else 4.0)
	return Rect2(Vector2(x, y), sz)


func _draw() -> void:
	if tex == null:
		return
	var r := _icon_rect()
	var c := r.get_center()
	var a := _amt
	var ph := _t * SPEED * TAU
	var rot := 0.0
	var sc := Vector2.ONE
	var off := Vector2.ZERO
	var glow := 0.0
	match kind:
		"spin":
			rot = _t * PI * 2.0 * a
		"turn":   # (a turntable: the picture's width swinging through its turn, never quite edge-on)
			var k := cos(_t * PI * 1.6)
			sc = Vector2(lerpf(1.0, signf(k) * maxf(absf(k), 0.15), a), 1.0)
			glow = 0.25 * a * (1.0 - absf(k))
		"push":
			sc = Vector2.ONE * (1.0 + 0.16 * a * (0.5 + 0.5 * sin(ph)))
		"bob":
			off = Vector2(0, -2.5 * a * sin(ph))
		"breathe":
			sc = Vector2.ONE * (1.0 + 0.12 * a * sin(ph))
			glow = 0.3 * a * (0.5 + 0.5 * sin(ph))
		"swing":
			rot = 0.28 * a * sin(ph)
		_:
			sc = Vector2.ONE * (1.0 + 0.1 * a * (0.5 + 0.5 * sin(ph)))
			glow = 0.35 * a * (0.5 + 0.5 * sin(ph * 0.5))
	var m := button.get_theme_color("icon_hover_color") if button.has_theme_color("icon_hover_color") else Color.WHITE
	if button.disabled:
		m = Color(1, 1, 1, 0.4)
	draw_set_transform(c + off, rot, sc)
	draw_texture_rect(tex, Rect2(-r.size * 0.5, r.size), false, m)
	if glow > 0.0:
		draw_texture_rect(tex, Rect2(-r.size * 0.5, r.size), false, Color(1.0, 0.85, 0.55, glow))
	draw_set_transform(Vector2.ZERO)
