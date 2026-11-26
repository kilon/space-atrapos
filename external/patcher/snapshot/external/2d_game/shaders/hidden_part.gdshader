shader_type spatial;
// A part not drawn (the old ink outline's hull: the photoreal look has none).
render_mode unshaded, cull_back, depth_draw_never;

void fragment() {
	discard;
}
