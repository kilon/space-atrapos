shader_type canvas_item;
// The hexagon curtain a menu opens and closes with (HexReveal): the menu's
// material while it plays, every part of the menu using it (use_parent_material)
// - each pixel shows only if its tile has opened, its colour tinted toward
// the theme's at the tile's rim as it opens. The tiles: a pointy-topped hex
// grid of radius r over the screen; each opens over `grow` seconds after its
// delay - its distance from the middle, sideways (spread), and a bit of
// randomness (jitter). Closing plays it backwards (t counts down).

uniform float t = 0.0;
uniform float r = 56.0;
uniform float spread = 0.36;
uniform float jitter = 0.08;
uniform float grow = 0.26;
uniform vec2 size = vec2(1920.0, 1080.0);
uniform vec4 edge : source_color = vec4(1.0, 0.62, 0.22, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// The centre of the tile p is in.
vec2 tile_of(vec2 p) {
	float w = sqrt(3.0) * r;
	float h = 1.5 * r;
	float row0 = floor(p.y / h + 0.5);
	vec2 best = vec2(0.0);
	float bd = 1e9;
	for (int dr = -1; dr <= 1; dr++) {
		float row = row0 + float(dr);
		float off = abs(mod(row, 2.0)) * 0.5 * w;
		float col = floor((p.x - off) / w + 0.5);
		for (int dc = -1; dc <= 1; dc++) {
			vec2 c = vec2((col + float(dc)) * w + off, row * h);
			float d = distance(p, c);
			if (d < bd) {
				bd = d;
				best = c;
			}
		}
	}
	return best;
}

// How far out p is in a pointy-topped hex of radius r round the origin: 1 on its sides.
float hex_dist(vec2 v) {
	v = abs(v);
	return max(v.x, dot(v, vec2(0.5, 0.8660254))) / (r * 0.8660254);
}

void fragment() {
	vec2 p = SCREEN_UV * size;
	vec2 c = tile_of(p);
	float delay = abs(c.x - size.x * 0.5) / max(size.x * 0.5, 1.0) * spread + hash(c) * jitter;
	float k = clamp((t - delay) / grow, 0.0, 1.0);
	k = 1.0 - pow(1.0 - k, 3.0);                    // (eased: quick, then settling)
	float hd = hex_dist(p - c);
	float open = (k >= 1.0) ? 1.0 : 1.0 - smoothstep(k * 1.02 - 0.03, k * 1.02, hd);
	float rim = (k > 0.0 && k < 1.0) ? (1.0 - smoothstep(0.0, 0.08, abs(hd - k))) * (1.0 - k) : 0.0;
	// (the tile flashes faintly as it opens, its rim glows)
	COLOR.rgb = mix(COLOR.rgb, edge.rgb, clamp(rim * 1.2 + open * (1.0 - k) * 0.25, 0.0, 1.0));
	COLOR.a *= open;
}
