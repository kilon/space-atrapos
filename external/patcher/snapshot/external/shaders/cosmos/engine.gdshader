// A ship's engine light (CosmosShip): the nozzle's glow (a camera-facing
// quad) or its plume (a cone, brightest at the nozzle), both by the thrust
// (instance parameter `level`).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;

instance uniform float level = 0.5;
uniform bool glow = true;
uniform vec4 tint : source_color = vec4(0.45, 0.75, 1.0, 1.0);

void vertex() {
	if (glow) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
}

void fragment() {
	float a;
	if (glow) {
		float r = length(UV * 2.0 - 1.0);
		a = exp(-r * r * 5.0) * smoothstep(1.0, 0.8, r);
	} else {
		float along = UV.y;                       // 0 at the wide end (the nozzle)
		float across = abs(UV.x * 2.0 - 1.0);
		a = (1.0 - along) * (1.0 - along) * 0.6 * (0.5 + 0.5 * sin(UV.x * TAU * 3.0 + TIME * 40.0) * 0.2);
	}
	ALBEDO = mix(tint.rgb, vec3(1.0), a * 0.5) * a * clamp(level, 0.0, 2.5);
}
