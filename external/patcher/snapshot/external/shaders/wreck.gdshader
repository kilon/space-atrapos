shader_type canvas_item;
// A wreck (Wreck): the ship's or station's own sprite, greyed out and
// darkened, scorched in blotches and torn open in places - the holes cut
// right through it - their edges smouldering.

uniform float seed = 0.0;
uniform float burn = 0.5;      // 0..1: how badly torn
uniform float fade = 1.0;      // fading away at the end

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	vec3 col = vec3(g) * 0.55 + vec3(0.03, 0.025, 0.02);
	float n = fbm(UV * 6.0 + seed);
	col *= mix(1.0, 0.3, smoothstep(0.42, 0.68, n));             // scorch
	float t = fbm(UV * 9.0 + seed * 1.7);
	float cut = 0.74 - burn * 0.12;
	float hole = smoothstep(cut - 0.02, cut, t);                 // torn through
	float edge = smoothstep(cut - 0.12, cut - 0.02, t) - hole;   // its smouldering rim
	col += vec3(1.0, 0.4, 0.1) * max(edge, 0.0) * 0.7 * (0.6 + 0.4 * sin(TIME * 2.0 + seed));
	COLOR = vec4(col, c.a * (1.0 - hole) * fade);
}
