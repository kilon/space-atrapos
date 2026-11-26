shader_type spatial;
// Curve modeling's curves drawn in the 3D view (CurveTools._sync_curve_lines): each segment a quad whose
// two sides are pushed apart on screen - a line `UV.x` pixels wide (plus `extra`: the dark rim drawn
// under it) however far it is - drawn with the scene, so the solids hide what's behind them. Pulled a
// hair towards the camera so a curve lying on a solid's edge stays in front of its faces.
// CUSTOM0: the segment's other end (xyz) and which side of it this corner is (w: -1 / 1).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float extra = 0.0;
uniform bool dark = false;
uniform float gain = 0.8;   // (the view's tone mapping washes bright colours out: given darker, they come out as meant)
varying vec4 col;

void vertex() {
	vec4 va = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 vb = MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0);
	va.xyz *= 0.996;   // (towards the camera: in front of the face it lies on)
	vb.xyz *= 0.996;
	vec4 a = PROJECTION_MATRIX * va;
	vec4 b = PROJECTION_MATRIX * vb;
	vec2 sa = a.xy / max(a.w, 1e-5) * VIEWPORT_SIZE;
	vec2 sb = b.xy / max(b.w, 1e-5) * VIEWPORT_SIZE;
	vec2 d = sb - sa;
	d = length(d) > 1e-4 ? normalize(d) : vec2(1.0, 0.0);
	vec2 n = vec2(-d.y, d.x);
	float w = (UV.x + extra) * 0.5;
	a.xy += n * CUSTOM0.w * w * 2.0 / VIEWPORT_SIZE * a.w;
	POSITION = a;
	col = COLOR;
}

void fragment() {
	ALBEDO = dark ? vec3(0.0) : pow(col.rgb, vec3(2.2)) * gain;   // (the colours given in sRGB)
	ALPHA = dark ? 0.5 * col.a : col.a;
}
