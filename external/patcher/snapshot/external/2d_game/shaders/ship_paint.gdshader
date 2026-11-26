shader_type canvas_item;
// Paint job for a ship sprite (Ship Designer): shifts the hue, scales
// saturation and brightness, and blends in a tint colour - the raster art's
// shading, panel lines and details stay intact.

uniform float hue = 0.0;        // hue shift, turns (-0.5 .. 0.5)
uniform float sat = 1.0;
uniform float bright = 1.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amt = 0.0;   // 0 .. 1
uniform float glow_keep = 0.85; // bright lights keep their colour

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 c = COLOR;   // (already the texture times the modulate)
	vec3 h = rgb2hsv(c.rgb);
	vec3 painted = hsv2rgb(vec3(fract(h.x + hue), clamp(h.y * sat, 0.0, 1.0), clamp(h.z * bright, 0.0, 1.0)));
	float lum = dot(painted, vec3(0.299, 0.587, 0.114));
	painted = mix(painted, tint.rgb * (0.35 + lum * 1.3), tint_amt * h.y);
	// Engine glows / lights (very bright) keep most of their own colour.
	float light = smoothstep(0.85, 1.0, h.z) * glow_keep;
	COLOR = vec4(mix(painted, c.rgb, light), c.a);
}
