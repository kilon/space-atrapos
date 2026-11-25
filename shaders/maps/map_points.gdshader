shader_type spatial;
// The 3D maps' points (the galaxy's far stars, an asteroid field's rocks): a
// soft round dot of size_px (times the vertex's UV.x) in the vertex colour.
render_mode unshaded, blend_add, depth_draw_never, fog_disabled, shadows_disabled;

uniform float size_px = 2.0;

void vertex() {
	POINT_SIZE = size_px * UV.x;
}

void fragment() {
	float r = length(POINT_COORD - 0.5) * 2.0;
	ALBEDO = COLOR.rgb * COLOR.a * (1.0 - smoothstep(0.3, 1.0, r));
}
