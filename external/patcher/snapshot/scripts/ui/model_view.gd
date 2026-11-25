class_name ModelView
extends SubViewportContainer
## A character's actual 3D model in a menu (the inventories' equipment screen:
## LoadoutPanel / EquipDoll): the model from art/<id>_3d/ (Stage3D's - the
## same cel shaders), standing in its idle animation in a little 3D world of
## its own. Drag with the left button to turn it round (a little up and down
## too); let go and it keeps its turn - kept between pages (static `yaw`).
## Drawn at REDRAW_HZ while it's on screen (the idle's breathing), never when hidden.
##   var v := ModelView.new(); v.model_id = "player"; parent.add_child(v)

const REDRAW_HZ := 30.0
const STAND_M := 1.95          # what the camera fits: the model's height (m)
const TURN := 0.012            # radians per px dragged
const CLIP := "gun_idle"

static var yaw := 0.45         # (the way it's turned - kept from one opening to the next)
static var pitch := 0.0

var model_id := "player"
var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _anim: AnimationPlayer
var _dragging := false
var _t := 0.0


static func available(id: String) -> bool:
	return Stage3D.has_model(id)


func _init() -> void:
	stretch = true
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_DRAG
	tooltip_text = "Drag with the left button to turn it round."


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.positional_shadow_atlas_size = 0
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = STAND_M * 1.06
	_cam.near = 0.1
	_cam.far = 40.0
	_vp.add_child(_cam)
	var sun := DirectionalLight3D.new()       # (as the stage's: from the upper left, fixed to the camera)
	sun.shadow_enabled = false
	_vp.add_child(sun)
	sun.look_at_from_position(Vector3(-3.4, 3.2, 2.4), Vector3.ZERO, Vector3.UP)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	if Stage3D.has_model(model_id):
		var model: Node3D = Stage3D._scene(model_id).instantiate()
		_pivot.add_child(model)
		var mesh: MeshInstance3D = model.find_child("Body", true, false)
		var mats := Stage3D.materials(model_id, mesh.mesh)
		for i in mats.size():
			mesh.set_surface_override_material(i, mats[i])
		mesh.extra_cull_margin = 2.0
		_anim = model.find_child("AnimationPlayer", true, false)
		if _anim:
			_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			var clip := CLIP if _anim.has_animation(CLIP) else "idle"
			if _anim.has_animation(clip):
				Stage3D.loop_clips(_anim, model_id, [clip])   # (a whole cycle long: no jump at the seam)
				_anim.play(clip)
				_anim.advance(0.0)
	_aim()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## The camera from the game's angle, a little above, turned by the drag.
func _aim() -> void:
	if _cam == null:
		return
	_pivot.rotation.y = yaw
	var el := deg_to_rad(Stage3D.ELEVATION * 0.5) + pitch
	var target := Vector3(0.0, STAND_M * 0.5, 0.0)
	_cam.look_at_from_position(target + Vector3(0.0, sin(el), cos(el)) * 12.0, target, Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		yaw = wrapf(yaw + event.relative.x * TURN, -PI, PI)
		pitch = clampf(pitch + event.relative.y * TURN * 0.5, -0.45, 0.6)
		_aim()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		accept_event()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	if _t < 1.0 / REDRAW_HZ:
		return
	if _anim and _anim.is_playing():
		_anim.advance(_t)
	_t = 0.0
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
