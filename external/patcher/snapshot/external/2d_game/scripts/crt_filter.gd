class_name CrtFilter
extends CanvasLayer
## The CRT filter (shaders/crt.gdshader) over the whole window: Settings
## adds one to the root at startup, so it lasts across every scene. It shows
## when Settings.crt_on is set, during attract mode when Settings.crt_attract
## is (the default), and while the CRT settings page is open (a preview).
## Its parameters come from Settings.crt (see Settings.CRT_PARAMS).

const SHADER := preload("res://shaders/crt.gdshader")

var rect: ColorRect
var _applied := {}


func _ready() -> void:
	layer = 127   # over everything but the scene-change fades (128)
	process_mode = Node.PROCESS_MODE_ALWAYS
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = ShaderMaterial.new()
	rect.material.shader = SHADER
	add_child(rect)
	_update()


func _process(_delta: float) -> void:
	_update()


## Whether the filter is showing right now.
static func wanted() -> bool:
	return Settings.crt_on or Settings.crt_preview or (Settings.crt_attract and AttractMode.active)


func _update() -> void:
	visible = wanted()
	if not visible:
		return
	for k in Settings.crt:
		if _applied.get(k) != Settings.crt[k]:
			_applied[k] = Settings.crt[k]
			rect.material.set_shader_parameter(k, Settings.crt[k])
