// The planet surface's front faces (the map is the top of a cube): orange
// brick courses with staggered joints, per-brick shade, lit top and dark
// bottom edges, a stone coping and a fade to shadow at the bottom - drawn
// per pixel on one polygon instead of thousands of brick shapes.
shader_type canvas_item;

uniform vec2 a;            // top edge start (local)
uniform vec2 b;            // top edge end
uniform float light = 1.0;
uniform float depth = 230.0;
const float COURSE = 26.0;
const float BRICK = 84.0;
const vec3 MORTAR = vec3(0.32, 0.16, 0.08);

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

float h1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 d = b - a;
	float len = length(d);
	float u = clamp(dot(lp - a, d / len), 0.0, len);
	float top = a.y + d.y * (u / len);
	float y = lp.y - top;                       // depth below the top edge
	float row = floor(y / COURSE);
	float yr = y - row * COURSE;
	float shift = mod(row, 2.0) == 1.0 ? BRICK * 0.5 : 0.0;
	float ub = u + shift;
	float bi = floor(ub / BRICK);
	float ur = ub - bi * BRICK;
	float rows = floor(depth / COURSE);
	vec3 col = MORTAR * light;
	bool in_brick = yr > 2.0 && yr < COURSE - 2.0 && ur > 2.5 && ur < BRICK - 2.5 && row < rows;
	if (in_brick) {
		float r1 = h1(vec2(bi, row) + a);
		float r2 = h1(vec2(row, bi) * 1.7 + b);
		vec3 base = mix(mix(vec3(0.88, 0.47, 0.18), vec3(0.95, 0.6, 0.25), r1), vec3(0.72, 0.32, 0.12), r2 * 0.5);
		float depth_k = 1.0 - 0.45 * row / rows;
		col = base * light * depth_k;
		if (yr < 4.0) col = mix(col, vec3(1.0, 0.82, 0.6), 0.55 * light);
		if (yr > COURSE - 4.0) col = mix(col, vec3(0.25, 0.1, 0.04), 0.5);
	}
	// Stone coping along the top.
	if (y < 10.0) col = vec3(0.98, 0.78, 0.5) * light;
	if (y < 1.5) col = vec3(1.0, 0.9, 0.7);
	// Fade to shadow at the bottom.
	col *= 1.0 - 0.55 * smoothstep(depth * 0.7, depth, y);
	COLOR = vec4(col, 1.0);
}
