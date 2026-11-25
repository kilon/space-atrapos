shader_type canvas_item;
// A gas giant's cloud deck seen from above (PlanetSurface._build_background,
// a placeholder until the painted background): bands of warm cloud drifting
// slowly, lighter toward the top of the screen, a haze below.

uniform vec3 tint : source_color = vec3(0.85, 0.55, 0.3);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 5; k++) {
		v += a * noise(p);
		p = p * 2.1 + vec2(13.0, 7.0);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME * 0.012;
	// bands along the screen's x, warped by drifting cloud noise
	vec2 p = vec2(uv.x * 3.0 + t, uv.y * 7.0);
	float warp = fbm(p * 0.9 + vec2(t * 2.0, 0.0));
	float band = 0.5 + 0.5 * sin((uv.y * 9.0 + warp * 1.6 + t * 0.3) * 3.1416);
	float cloud = fbm(p * 1.7 + vec2(t * 3.0, warp));
	vec3 deep = tint * 0.45;
	vec3 light = mix(tint, vec3(1.0, 0.92, 0.8), 0.45);
	vec3 col = mix(deep, light, band * 0.55 + cloud * 0.55);
	col = mix(col, tint * 0.35, smoothstep(0.55, 1.0, uv.y) * 0.6);   // the haze below
	col += vec3(0.08, 0.05, 0.02) * smoothstep(0.3, 0.0, uv.y);        // lit from above
	COLOR = vec4(col, 1.0);
}
