// The sky of a star system in the 3D game (Cosmos): stars (two layers of
// points hashed from the view direction, coloured), the galaxy's band and the
// system's nebulae (the 3D noise, tinted) - no textures to load, a few
// lookups a pixel.
shader_type sky;

uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform vec4 neb_a : source_color = vec4(0.3, 0.15, 0.5, 1.0);
uniform vec4 neb_b : source_color = vec4(0.1, 0.35, 0.5, 1.0);
uniform vec3 band_axis = vec3(0.3, 0.9, 0.2);
uniform float seed = 0.0;
uniform float neb_strength = 1.0;

vec3 hash3(vec3 p) {
	uvec3 q = uvec3(ivec3(p) + 32768) * uvec3(1597334673u, 3812015801u, 2798796415u);
	q = (q.x ^ q.y ^ q.z) * uvec3(1597334673u, 3812015801u, 2798796415u);
	return vec3(q) * (1.0 / 4294967295.0);
}

// One layer of stars: a star in some of the cells of a 3D grid of k cells a
// radian, round dots never thinner than ~1.3 pixels (PX: a pixel's angle at
// 1080 lines and the game's ~70 degree view) - smaller ones are spread wider
// and dimmed to the same light: no star blinks out between pixels (aliasing).
const float PX = 0.00115;

float stars(vec3 d, float k, float density, out vec3 tint) {
	vec3 p = d * k;
	vec3 id = floor(p);
	vec3 h = hash3(id + seed);
	tint = vec3(1.0);
	if (h.x > density) return 0.0;
	vec3 c = id + 0.5 + (hash3(id + 7.0) - 0.5) * 0.7;
	vec3 to = c - p;
	float dd = length(to - d * dot(to, d));      // across the view ray (cells)
	float r0 = 0.16;
	float r = max(r0, 1.3 * PX * k);
	float s = exp(-dd * dd / (r * r) * 2.5) * (r0 * r0) / (r * r) * (0.3 + 1.7 * h.y * h.y);
	tint = mix(vec3(1.0, 0.75, 0.55), vec3(0.7, 0.82, 1.0), h.z);
	return s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 t1, t2, t3;
	vec3 col = stars(d, 180.0, 0.05, t1) * t1 + stars(d, 420.0, 0.06, t2) * t2 * 0.6 + stars(d, 75.0, 0.012, t3) * t3 * 1.5;
	float band = exp(-pow(dot(d, normalize(band_axis)) * 3.2, 2.0));
	float n = texture(noise_tex, d * 1.3 + seed * 0.01).r;
	float n2 = texture(noise_tex, d * 3.7 + 0.3).r;
	col += vec3(0.5, 0.55, 0.7) * band * (0.04 + 0.08 * n2) + band * band * stars(d, 600.0, 0.12, t1) * 0.5;
	float nn = texture(noise_tex, d * 0.55 + 0.17).r * 0.7 + n * 0.3;
	float neb = pow(smoothstep(0.5, 0.95, nn), 1.6);
	col += mix(neb_a.rgb, neb_b.rgb, smoothstep(0.3, 0.7, n2)) * neb * 0.16 * neb_strength;
	COLOR = col;
}
