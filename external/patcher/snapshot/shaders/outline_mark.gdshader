shader_type spatial;
// A selection outline's first pass (outline.gdshader the next): the shape's own visible pixels marked in
// the stencil buffer (nothing drawn), so the outline shows only outside the shape as seen - never over
// its own folds, holes and the parts of it behind its front.
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
stencil_mode write, compare_always, 1;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
