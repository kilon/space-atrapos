shader_type canvas_item;
// HealthGauge: a silhouette (the texture's opaque part) filled with liquid up to
// `level` (0..1 of its height) - a wavy, moving surface, darker in the depth, a
// light band at the top, rising bubbles - empty glass above; its edge lit.
uniform float level = 1.0;
uniform vec4 liquid : source_color = vec4(0.9, 0.12, 0.1, 1.0);
uniform vec4 glass : source_color = vec4(0.05, 0.06, 0.09, 0.75);
uniform vec4 rim : source_color = vec4(1.0, 0.55, 0.45, 1.0);
uniform vec2 px = vec2(0.012, 0.012);   // the outline's width, in UV
uniform float seed = 0.0;

void fragment() {
	float a = texture(TEXTURE, UV).a;
	float n = min(min(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a),
		min(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a));
	float inside = step(0.35, a);
	float edge = inside * (1.0 - step(0.35, n));
	float t = TIME + seed;
	float wave = 0.016 * sin(UV.x * 17.0 + t * 3.1) + 0.01 * sin(UV.x * 29.0 - t * 2.3);
	float surf = 1.0 - level + wave * step(0.001, level) * step(level, 0.999);
	float wet = step(surf, UV.y);
	vec3 col = mix(liquid.rgb * 1.3, liquid.rgb * 0.55, clamp((UV.y - surf) * 1.6, 0.0, 1.0));
	col += smoothstep(0.035, 0.0, abs(UV.y - surf)) * 0.45;
	vec2 cell = floor(vec2(UV.x * 22.0, UV.y * 22.0 + t * 1.7));
	float bub = step(0.975, fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453));
	col += bub * 0.3;
	vec4 fill = mix(glass, vec4(col, 0.96), wet);
	vec4 o = mix(fill, rim, edge);
	o.a *= inside;
	COLOR = o;
}
