// A soft glow (a star's, an engine's): a camera-facing quad whose light falls
// off from the middle, added over the scene.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float intensity = 1.0;
uniform float core = 0.18;      // the bright middle's share of the radius
uniform bool see_through = false;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float g = exp(-r * r * 6.0) * 0.6 + exp(-r * 18.0) * 0.5 + smoothstep(core, 0.0, r) * 0.6;
	g *= smoothstep(1.0, 0.85, r);
	ALBEDO = tint.rgb * g * intensity;
}
