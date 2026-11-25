shader_type canvas_item;
// HealthGauge: the shield - a ring (inner..outer, of the rect's half-size)
// filled with liquid up to `level` (0..1 of the circle's height), a wavy moving
// surface, empty glass above, its two rims lit.
uniform float level = 1.0;
uniform float inner = 0.78;
uniform float outer = 0.97;
uniform vec4 liquid : source_color = vec4(0.2, 0.55, 1.0, 1.0);
uniform vec4 glass : source_color = vec4(0.04, 0.06, 0.12, 0.7);
uniform vec4 rim : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform float seed = 3.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = length(p);
	float aa = fwidth(d);
	float band = smoothstep(inner - aa, inner, d) * (1.0 - smoothstep(outer, outer + aa, d));
	float edges = (1.0 - smoothstep(0.0, aa * 1.5, abs(d - inner))) + (1.0 - smoothstep(0.0, aa * 1.5, abs(d - outer)));
	float t = TIME + seed;
	float wave = 0.035 * sin(p.x * 7.0 + t * 2.7) + 0.02 * sin(p.x * 13.0 - t * 1.9);
	float surf = outer - 2.0 * outer * level + wave * step(0.001, level) * step(level, 0.999);
	float wet = step(surf, p.y);
	vec3 col = mix(liquid.rgb * 1.3, liquid.rgb * 0.6, clamp((p.y - surf) * 0.7, 0.0, 1.0));
	col += smoothstep(0.07, 0.0, abs(p.y - surf)) * 0.5;
	vec4 fill = mix(glass, vec4(col, 0.95), wet);
	vec4 o = fill;
	o.a *= band;
	o = mix(o, rim, clamp(edges, 0.0, 1.0) * 0.9);
	COLOR = o;
}
