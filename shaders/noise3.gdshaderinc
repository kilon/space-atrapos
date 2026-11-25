// 3D value noise for the planet and star shaders (surfaces on a sphere).

float hash31(vec3 p) {
	uvec3 q = uvec3(ivec3(p)) * uvec3(1597334673u, 3812015801u, 2798796415u);
	uint n = (q.x ^ q.y ^ q.z) * 1597334673u;
	return float(n) * (1.0 / 4294967295.0);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(hash31(i), hash31(i + vec3(1, 0, 0)), u.x);
	float b = mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), u.x);
	float c = mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), u.x);
	float d = mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), u.x);
	return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

const mat3 OCT = mat3(vec3(0.0, 0.8, 0.6), vec3(-0.8, 0.36, -0.48), vec3(-0.6, -0.48, 0.64));

float fbm3(vec3 p, int oct) {
	float v = 0.0, a = 0.5, n = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= oct) break;
		v += a * vnoise3(p);
		n += a;
		p = OCT * p * 2.03 + vec3(11.7, 3.1, 7.9);
		a *= 0.5;
	}
	return v / n;
}

// Ridged multifractal: sharp crests where the noise crosses its middle.
float ridged3(vec3 p, int oct) {
	float v = 0.0, a = 0.5, n = 0.0, w = 1.0;
	for (int i = 0; i < 8; i++) {
		if (i >= oct) break;
		float r = 1.0 - abs(vnoise3(p) * 2.0 - 1.0);
		r *= r;
		v += a * r * w;
		n += a;
		w = clamp(r * 1.6, 0.0, 1.0);
		p = OCT * p * 2.1 + vec3(5.3, 8.7, 1.9);
		a *= 0.5;
	}
	return v / n;
}
