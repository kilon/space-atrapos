shader_type spatial;
// The 3D maps' lines (MapKit.Lines): every segment a quad turned to face the
// camera and widened in screen pixels - lines of any width, soft-edged, that
// stay the same thickness at every zoom; dashed (flowing) where asked.
// Per vertex: VERTEX this end, CUSTOM0.xyz the other end, CUSTOM0.w the side
// (-1 / 1: which way to widen, as seen from this end); UV.x how far along
// the line (in dashes), UV.y the width (px) signed by the side; UV2.x the
// dash period (0: solid), UV2.y how fast the dashes flow.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled, skip_vertex_transform;

varying float v_side;
varying float v_along;
varying vec2 v_dash;

void vertex() {
	vec4 a = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec4 b = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0));
	vec2 sa = a.xy / max(a.w, 1e-4);
	vec2 sb = b.xy / max(b.w, 1e-4);
	vec2 d = (sb - sa) * VIEWPORT_SIZE;
	d = length(d) > 1e-5 ? normalize(d) : vec2(1.0, 0.0);
	vec2 n = vec2(-d.y, d.x);
	float w = abs(UV.y) + 1.5;   // (a pixel and a half more: the soft edge)
	a.xy += n * CUSTOM0.w * w / VIEWPORT_SIZE * a.w;
	POSITION = a;
	v_side = sign(UV.y);
	v_along = UV.x;
	v_dash = UV2;
}

void fragment() {
	float edge = 1.0 - smoothstep(0.45, 1.0, abs(v_side));
	float dash = 1.0;
	if (v_dash.x > 0.0) {
		float ph = fract((v_along - TIME * v_dash.y) / v_dash.x);
		dash = smoothstep(0.0, 0.06, ph) * (1.0 - smoothstep(0.5, 0.56, ph));
	}
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * edge * dash;
}
