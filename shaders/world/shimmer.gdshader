// Heat shimmer: the air behind a jet's nozzle bending what's seen through it -
// a camera-facing quad that reads the screen behind it, offset by drifting noise,
// strongest in its middle, nothing at its edges.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform float strength = 0.012;
instance uniform float level = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float fall = smoothstep(1.0, 0.2, length(c));
	vec2 n = vec2(texture(noise_tex, vec3(UV * 0.6, TIME * 0.35)).r,
		texture(noise_tex, vec3(UV * 0.8 + 0.37, TIME * 0.45 + 0.5)).r) - 0.5;
	vec2 off = n * strength * fall * level;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	ALPHA = fall * level;
}
