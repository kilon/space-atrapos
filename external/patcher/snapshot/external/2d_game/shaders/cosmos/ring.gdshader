// A gas giant's rings (CosmosPlanet): bands and gaps across the radius (UV.x
// inner 0 -> outer 1), the planet's shadow across them.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec4 ring_a : source_color = vec4(0.85, 0.78, 0.65, 1.0);
uniform vec4 ring_b : source_color = vec4(0.55, 0.5, 0.45, 1.0);
uniform float density = 1.0;
uniform float seed = 0.0;
uniform float r_planet = 5000.0;

float h1(float x) {
	return fract(sin(x * 127.1 + seed * 3.7) * 43758.5453);
}

float vn(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(h1(i), h1(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	float t = UV.x;
	float bands = 0.55 + 0.45 * vn(t * 38.0);
	bands *= 0.7 + 0.3 * vn(t * 140.0 + 9.0);
	float gap = smoothstep(0.015, 0.0, abs(t - 0.62)) + smoothstep(0.01, 0.0, abs(t - 0.86)) * 0.7;
	float a = bands * (1.0 - gap) * smoothstep(0.0, 0.04, t) * smoothstep(1.0, 0.94, t) * density;
	vec3 col = mix(ring_b.rgb, ring_a.rgb, vn(t * 9.0 + 4.0));
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz - NODE_POSITION_WORLD;
	float tc = -dot(wp, sun_dir);
	float shadow = (tc > 0.0 && length(wp + tc * sun_dir) < r_planet) ? 0.12 : 1.0;
	ALBEDO = col * shadow;
	ALPHA = a * 0.85;
}
