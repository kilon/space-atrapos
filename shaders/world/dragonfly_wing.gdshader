// The dragonfly's four wings (CosmosDragonfly): glass-thin membrane with a
// faint rainbow sheen, veined - the long veins along the span crowded toward
// the leading edge, cross-veins between them, polygonal cells toward the
// trailing edge - the nodus, a dark stigma near each tip, an amber base.
// UV: (along the span 0 root .. 1 tip, across the chord 0 leading .. 1 trailing);
// UV2: (side -1 / 1, 0 fore / 1 hind). Beaten round their hinges here: a
// stroke up and down, the wing twisted along it (feathering), the tip lagging;
// the hind pair leads the fore a quarter beat. `phase` the beat (CosmosCreature
// advances it), `flap` how much (0: held out still).
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.6, 0.85, 0.9, 1.0);
uniform vec4 stigma : source_color = vec4(0.1, 0.07, 0.05, 1.0);
uniform vec3 fore_hinge = vec3(0.028, 0.112, -0.44);
uniform vec3 hind_hinge = vec3(0.028, 0.106, -0.335);
uniform float phase = 0.0;
uniform float flap = 1.0;
uniform float flash = 0.0;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 rot_x(vec3 p, float a) {
	float c = cos(a), s = sin(a);
	return vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

vec3 rot_z(vec3 p, float a) {
	float c = cos(a), s = sin(a);
	return vec3(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
}

void vertex() {
	float side = UV2.x;
	float hind = UV2.y;
	vec3 h = mix(fore_hinge, hind_hinge, hind);
	h.x *= side;
	float ph = phase + hind * 1.57;
	float s = UV.x;
	float stroke = (sin(ph) * 0.62 + 0.1) * flap + (1.0 - flap) * (-0.04 - hind * 0.03);
	stroke += sin(ph - 0.9) * 0.12 * flap * s * s;      // (the tip lagging: the wing bends)
	float twist = cos(ph) * 0.42 * flap * (0.35 + 0.65 * s);
	vec3 p = VERTEX - h;
	vec3 nn = NORMAL;
	p = rot_x(p, twist);
	nn = rot_x(nn, twist);
	p = rot_z(p, side * stroke);
	nn = rot_z(nn, side * stroke);
	VERTEX = p + h;
	NORMAL = nn;
}

float line(float d, float w) {
	float aa = fwidth(d) * 1.2 + 1e-5;
	return 1.0 - smoothstep(w, w + aa, d);
}

void fragment() {
	float s = UV.x;
	float c = UV.y;
	float hind = UV2.y;
	// The long veins: costa on the leading edge, then crowded behind it, spreading toward the trailing edge.
	float v = line(c, 0.035) * 1.0;
	v = max(v, line(abs(c - 0.06), 0.008));
	v = max(v, line(abs(c - 0.13), 0.008));
	v = max(v, line(abs(c - 0.24 - 0.03 * s), 0.007));
	v = max(v, line(abs(c - 0.38 + 0.05 * s), 0.006));
	v = max(v, line(abs(c - 0.55 + 0.08 * s * s), 0.006));
	v = max(v, line(abs(c - 0.72 - 0.04 * s), 0.005) * smoothstep(0.0, 0.1, s));
	v = max(v, line(1.0 - c, 0.02));   // (the trailing edge's rim)
	// Cross-veins between them, a little irregular; polygon cells toward the trailing edge.
	float band = floor(c * 9.0);
	float x = s * (60.0 + 10.0 * hash2(vec2(band, hind))) + hash2(vec2(band, 3.0 + hind)) * 0.7;
	float cross = line(0.5 - abs(fract(x) - 0.5), 0.03) * (1.0 - smoothstep(0.5, 0.62, c));
	vec2 q = vec2(s * 55.0, c * 14.0);
	vec2 qi = floor(q);
	float d1 = 9.0, d2 = 9.0;
	for (int yy = -1; yy <= 1; yy++) {
		for (int xx = -1; xx <= 1; xx++) {
			vec2 o = qi + vec2(float(xx), float(yy));
			vec2 pnt = o + 0.15 + 0.7 * vec2(hash2(o), hash2(o + 17.0));
			float d = length(q - pnt);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	float cells = line(d2 - d1, 0.07) * smoothstep(0.5, 0.62, c);
	float fine = clamp(1.6 - (fwidth(q.x) + fwidth(q.y)) * 1.2, 0.0, 1.0);   // (too fine to see: faded, not a grey mesh)
	v = max(v, max(cross, cells) * 0.6 * fine);
	// The nodus (a notch on the leading edge, mid-wing) and the stigma near the tip.
	float nodus = (1.0 - smoothstep(0.005, 0.012, abs(s - 0.47))) * (1.0 - smoothstep(0.1, 0.16, c));
	float stg = smoothstep(0.81, 0.815, s) * (1.0 - smoothstep(0.885, 0.89, s)) * (1.0 - smoothstep(0.12, 0.13, c));
	v = max(v, nodus);
	float ndv = abs(dot(NORMAL, VIEW));
	float fres = pow(1.0 - ndv, 3.0);
	// The membrane: clear glass, a thin film's rainbow with the angle and place.
	vec3 rainbow = 0.5 + 0.5 * cos(6.2832 * (vec3(0.0, 0.33, 0.67) + (1.0 - ndv) * 1.4 + s * 0.8 + c * 0.35));
	vec3 mem = mix(tint.rgb * 0.25 + 0.15, rainbow * 0.6, 0.45);
	float amber = (1.0 - smoothstep(0.03, 0.14, s));
	mem = mix(mem, vec3(0.6, 0.38, 0.12), amber * 0.6);
	vec3 vein = vec3(0.02, 0.02, 0.025) + tint.rgb * 0.03;
	vec3 col = mix(mem, vein, v);
	col = mix(col, stigma.rgb, stg);
	float a = 0.07 + fres * 0.3 + amber * 0.25;
	a = max(a, v * 0.85);
	a = max(a, stg * 0.97);
	// (the edge of the grid: the outline is the mesh's own, softened)
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.06, 0.6, max(v, stg));
	SPECULAR = mix(0.75, 0.15, max(v, stg));   // (the veins dull: the glass between them shines)
	EMISSION = vec3(1.0, 0.25, 0.15) * flash * 0.5;
}
