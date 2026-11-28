shader_type spatial;
// The automaton's energy shield (CosmosWalker): a bubble round it, seen only for a moment
// when a hit lands on it - a hexagon lattice lit up round the hit (its way: hit_dir, the
// bubble's own space), a ripple running out from it over the bubble, the rim brighter
// (fresnel). `age` 0 at the hit .. 1 gone; `broke` 1: the shield giving out (red, all of it).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform vec3 hit_dir = vec3(0.0, 0.0, 1.0);
instance uniform float age = 1.0;
instance uniform float broke = 0.0;
uniform vec3 tint : source_color = vec3(0.35, 0.75, 1.0);
uniform vec3 broke_tint : source_color = vec3(1.0, 0.35, 0.25);

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

// The distance to the nearest hexagon edge (0 on an edge) for a point on a hex lattice.
float hex_edge(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 c = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - c.xy * s, p - (c.zw + 0.5) * s);
	vec2 q = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
	q = abs(q);
	return 0.5 - max(dot(q, s * 0.5), q.x);
}

void fragment() {
	vec3 n = normalize(lp);
	float a = clamp(age, 0.0, 1.0);
	// (the lattice wrapped round the bubble: longitude and height)
	vec2 uv = vec2(atan(n.x, n.z) * 3.2, n.y * 6.0);
	float edge = 1.0 - smoothstep(0.0, 0.07, hex_edge(uv * 2.2));
	float near = dot(n, normalize(hit_dir));          // 1 at the hit .. -1 opposite
	float d = acos(clamp(near, -1.0, 1.0)) / 3.14159; // 0 at the hit .. 1 opposite
	float spot = (1.0 - smoothstep(0.0, 0.24, d)) * (1.0 - a);
	float ring = (1.0 - smoothstep(0.0, 0.08, abs(d - a * 0.9))) * (1.0 - a);
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	float all_k = broke * (1.0 - a);
	float k = spot * (0.25 + edge * 1.2) + ring * (0.35 + edge * 0.8) + fres * (0.25 * (1.0 - a) * (spot + 0.2) + all_k * 0.8) + all_k * edge * 0.9;
	vec3 col = mix(tint, broke_tint, broke);
	ALBEDO = col * k * 1.6;
	ALPHA = clamp(k, 0.0, 1.0);
}
