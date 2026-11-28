@tool
class_name CosmosGodRays
extends CompositorEffect
## The sun's rays through the gaps in the clouds and the trees (the camera's
## Compositor: after the transparent things are drawn - the clouds, the air -
## so both shape them): the compute shader shaders/world/god_rays.glsl, its
## three passes (the mask, the rays, added to the frame). Cosmos sets where the
## sun is on screen and how strong they are each frame (`sun_uv`, `strength`,
## `tint`): in the air of a world by day, the sun near or on screen; none in
## space, at night, under a storm. Not in the browser's renderer (no compute).

const SHADER := "res://shaders/world/god_rays.glsl"

var sun_uv := Vector2(0.5, 0.5)
var strength := 0.0
var tint := Color(1.0, 0.92, 0.78)
var reach := 0.55                # (how far round the sun on screen the light's taken from)

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _sampler := RID()


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_rd = RenderingServer.get_rendering_device()
	if _rd:
		RenderingServer.call_on_render_thread(_setup)


func _setup() -> void:
	var file: RDShaderFile = load(SHADER)
	if file == null:
		return
	var spirv := file.get_spirv()
	if spirv == null or spirv.compile_error_compute != "":
		push_error("god_rays.glsl: " + (spirv.compile_error_compute if spirv else "no SPIR-V"))
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler = _rd.sampler_create(ss)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd:
		for r in [_pipeline, _shader, _sampler]:
			if r.is_valid():
				_rd.free_rid(r)


func _render_callback(_type: int, render_data: RenderData) -> void:
	if strength <= 0.002 or not _pipeline.is_valid():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var half := Vector2i(maxi(1, size.x / 2), maxi(1, size.y / 2))
	var usage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	if not buffers.has_texture("god_rays", "mask") or buffers.get_texture_format("god_rays", "mask").width != half.x:
		if buffers.has_texture("god_rays", "mask"):
			buffers.clear_context("god_rays")
		buffers.create_texture("god_rays", "mask", RenderingDevice.DATA_FORMAT_R16_SFLOAT, usage, RenderingDevice.TEXTURE_SAMPLES_1, half, 1, 1, true, false)
		buffers.create_texture("god_rays", "rays", RenderingDevice.DATA_FORMAT_R16_SFLOAT, usage, RenderingDevice.TEXTURE_SAMPLES_1, half, 1, 1, true, false)
	for view in buffers.get_view_count():
		var color := buffers.get_color_layer(view)
		var depth := buffers.get_depth_layer(view)
		var mask := buffers.get_texture_slice("god_rays", "mask", view, 0, 1, 1)
		var rays := buffers.get_texture_slice("god_rays", "rays", view, 0, 1, 1)
		var u_depth := RDUniform.new()
		u_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_depth.binding = 0
		u_depth.add_id(_sampler)
		u_depth.add_id(depth)
		var u_color := _image(1, color)
		var u_mask := _image(2, mask)
		var u_rays := _image(3, rays)
		var set := UniformSetCacheRD.get_cache(_shader, 0, [u_depth, u_color, u_mask, u_rays])
		for mode in 3:
			var pc := PackedFloat32Array([size.x, size.y, half.x, half.y, sun_uv.x, sun_uv.y, strength, float(mode),
				tint.r, tint.g, tint.b, reach])
			var groups := Vector2i(half) if mode < 2 else size
			var list := _rd.compute_list_begin()
			_rd.compute_list_bind_compute_pipeline(list, _pipeline)
			_rd.compute_list_bind_uniform_set(list, set, 0)
			_rd.compute_list_set_push_constant(list, pc.to_byte_array(), pc.size() * 4)
			_rd.compute_list_dispatch(list, (groups.x + 7) / 8, (groups.y + 7) / 8, 1)
			_rd.compute_list_end()


static func _image(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u
