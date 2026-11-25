// Procedural deep-space objects for the background (additive, on a square
// ColorRect; everything fades out before the rect's edges), modelled on the
// reference images in external/images/nebula_refs/:
//   mode 0 - supernova remnant: an irregular shell of glowing filaments
//   mode 1 - planetary nebula: nested shells and bubbles around a hot
//            central star, twin jets, faint outer rings
//   mode 2 - emission nebula: vast warped clouds, wisps, dust lanes, a
//            bright core and embedded young stars
//   mode 3 - spiral galaxy: a tilted disc with logarithmic arms, a bright
//            bulge, dust lanes, pink star-forming knots and satellites
// Parameters come from NebulaGen (scripts/nebula_gen.gd).
shader_type canvas_item;
render_mode blend_add;

#include "res://shaders/noise.gdshaderinc"

uniform int mode = 2;
uniform float seed = 0.0;
uniform float intensity = 0.7;
uniform float rot = 0.0;
uniform vec2 stretch = vec2(1.0, 1.0);
uniform vec4 color_a : source_color = vec4(0.9, 0.35, 0.1, 1.0);    // outer
uniform vec4 color_b : source_color = vec4(0.25, 0.55, 1.0, 1.0);   // inner
uniform vec4 color_c : source_color = vec4(1.0, 0.95, 0.9, 1.0);    // highlights / core
uniform vec4 color_d : source_color = vec4(0.4, 0.8, 0.3, 1.0);     // patches
uniform float filaments = 0.8;
uniform float dust = 0.4;
uniform float core = 0.6;
uniform float stars = 0.4;
uniform float jets = 0.0;
uniform float shells = 1.0;
uniform float arms = 2.0;
uniform float wind = 2.6;
uniform float incline = 0.38;
uniform float satellites = 0.0;
uniform float drift = 0.01;

float ridged(vec2 p) {
	return 1.0 - abs(fbm(p) * 2.0 - 1.0);
}

// Sparse bright points (young stars in the cloud).
float points(vec2 p, float density) {
	vec2 c = floor(p);
	vec2 f = fract(p);
	float h = hash21(c + seed * 13.0);
	if (h > density) return 0.0;
	vec2 at = vec2(hash21(c + 3.1), hash21(c + 7.7)) * 0.6 + 0.2;
	float d = length(f - at);
	return exp(-d * d * 900.0) * 1.5 + exp(-d * 18.0) * 0.12;
}

mat2 rot2(float a) { return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))); }

vec4 remnant(vec2 p) {
	vec2 w = vec2(fbm(p * 1.6 + seed), fbm(p * 1.6 + seed + 5.2)) - 0.5;
	float d = length(p + w * 0.5) + (fbm(p * 3.0 + seed * 2.0) - 0.5) * 0.35;
	float mask = smoothstep(0.95, 0.55, d);
	float shell = smoothstep(0.35, 0.85, d) * mask;
	vec2 q = p * 3.0 + w * 3.0 + seed;
	vec2 w2 = vec2(fbm(q * 1.7 + 3.0), fbm(q * 1.7 + 8.0)) - 0.5;
	float f1 = pow(ridged(rot2(0.7) * q + w2 * 2.0), 6.0);
	float f2 = pow(ridged(rot2(2.1) * q * 2.3 + w2 * 3.0 + 4.0), 9.0);
	float f3 = pow(ridged(rot2(4.0) * q * 5.3 + w2 * 5.0 - 2.0), 12.0);
	float hair = pow(ridged(rot2(1.3) * q * 11.0 + w2 * 8.0), 14.0);
	float fil = (f1 + f2 * 0.9 + f3 * 0.8 + hair * 0.7) * filaments;
	float cloud = fbm(q * 0.7 + 9.0);
	vec3 col = mix(color_b.rgb, color_a.rgb, smoothstep(0.35, 0.8, d + (cloud - 0.5) * 0.4));
	col = mix(col, color_d.rgb, smoothstep(0.6, 0.72, fbm(p * 2.2 + seed + 3.0)) * shell);
	float dens = mask * (cloud * 0.4 + min(fil, 1.6) * 1.1);
	float lane = smoothstep(0.55, 0.75, ridged(q * 0.9 + 11.0));
	dens *= 1.0 - lane * dust * 0.8;
	float cg = exp(-length(p) * 6.0) * core;
	col = mix(col, color_c.rgb, clamp(cg, 0.0, 1.0));
	dens += cg * mask;
	col = mix(col, color_c.rgb, clamp((f1 * f2 * 2.0 + hair * 0.25) * (1.0 - d), 0.0, 0.7));
	return vec4(col, dens);
}

vec4 planetary(vec2 p) {
	float r = length(p);
	float ang = atan(p.y, p.x);
	vec3 acc = vec3(0.0);
	float a = 0.0;
	float wob = (fbm(vec2(ang * 3.0 + seed, r * 4.0)) - 0.5) * 0.06;
	// Inner bubbles: overlapping circular rims around the centre.
	for (int k = 0; k < 4; k++) {
		float fk = float(k);
		vec2 off = vec2(cos(fk * 1.57 + seed), sin(fk * 1.57 + seed)) * 0.11;
		float rr = length(p - off) + wob;
		float rim = exp(-pow((rr - 0.17) / 0.03, 2.0)) * shells;
		acc += color_a.rgb * exp(-pow((rr - 0.19) / 0.012, 2.0)) * 0.5 * shells;
		float fill = smoothstep(0.17, 0.0, rr) * 0.25;
		acc += mix(color_b.rgb, color_c.rgb, rim * 0.6) * (rim + fill);
		a += rim + fill;
	}
	// Middle shell (orange-tinted rim) and textured outer rings.
	float m = exp(-pow((r + wob * 2.0 - 0.34) / 0.035, 2.0));
	float mhalo = exp(-pow((r + wob * 2.0 - 0.34) / 0.12, 2.0)) * 0.25;
	acc += mix(color_b.rgb, color_c.rgb, 0.35) * m * 1.3 * shells + color_b.rgb * mhalo * shells;
	a += mhalo;
	a += m;
	float streaks = 0.75 + 0.35 * fbm(vec2(ang * 40.0 + seed, r * 3.0));
	for (int k = 0; k < 3; k++) {
		float R = 0.55 + float(k) * 0.13;
		float o = exp(-pow((r + wob * 3.0 - R) / 0.05, 2.0)) * (0.45 - float(k) * 0.1) * streaks;
		acc += color_d.rgb * o * shells;
		a += o;
	}
	// Central star.
	float cs = exp(-r * r * 3000.0) * 3.0 + exp(-r * 14.0) * 0.6 * core;
	acc += color_c.rgb * cs;
	a += cs;
	float mask = smoothstep(1.0, 0.8, r);
	return vec4(acc / max(a, 1e-3), min(a, 1.6) * mask);
}

vec4 emission(vec2 p) {
	vec2 q = p * 1.8 + seed;
	vec2 w1 = vec2(fbm(q), fbm(q + vec2(5.2, 1.3))) - 0.5;
	vec2 w2 = vec2(fbm(q + w1 * 3.0 + 2.0), fbm(q + w1 * 3.0 + 7.0)) - 0.5;
	float n = fbm(q + w2 * 2.4);
	vec2 w3 = vec2(fbm(rot2(0.5) * q * 2.6 + 1.0), fbm(rot2(2.3) * q * 2.6 + 6.0)) - 0.5;
	float wisp = (pow(ridged(rot2(0.6) * q * 2.2 + w2 * 3.0 + w3 * 2.5), 6.0) * 0.7 + pow(ridged(rot2(1.9) * q * 4.7 + w2 * 5.0 + w3 * 4.0), 10.0) * 0.8) * filaments;
	float d = length(p) + (n - 0.5) * 0.7;
	float mask = smoothstep(1.05, 0.35, d);
	float dens = smoothstep(0.28, 0.72, n) * mask * 1.3;
	vec3 col = mix(color_a.rgb, color_b.rgb, smoothstep(0.35, 0.75, fbm(q * 1.4 + w1 * 2.0 + 4.0)));
	col = mix(col, color_d.rgb, smoothstep(0.62, 0.78, fbm(q * 2.0 - 3.0)) * 0.7);
	dens += wisp * mask * 1.2;
	col = mix(col, color_a.rgb * 1.2, wisp * 0.5);
	// Dust lanes: dark bands that eat the glow.
	float lane = smoothstep(0.55, 0.75, ridged(q * 1.1 + w1 * 2.0 + 11.0));
	dens *= 1.0 - lane * dust;
	// Bright core where the young stars light it.
	vec2 cp = vec2(0.12, -0.08);
	float c = exp(-length(p - cp) * 5.0) * core;
	col = mix(col, color_c.rgb, clamp(c * 1.2, 0.0, 1.0));
	dens += c * mask * 0.9;
	float st = points(p * 14.0, 0.25) * stars * mask;
	return vec4(col + color_c.rgb * st, dens + st);
}

vec4 galaxy(vec2 p) {
	vec2 q = vec2(p.x, p.y / incline);
	float r = length(q);
	float th = atan(q.y, q.x);
	float spiral = th * arms - log(max(r, 0.02)) * wind * arms - TIME * drift;
	float arm = pow(0.5 + 0.5 * cos(spiral + seed), 3.0);
	float lane = pow(0.5 + 0.5 * cos(spiral + seed + 0.9), 10.0) * dust;
	float clump = fbm(q * 9.0 + seed);
	float disc = exp(-r * 1.5) * smoothstep(1.0, 0.6, r);
	float bulge = exp(-r * r * 60.0) * core * 2.2 + exp(-r * 9.0) * core * 0.8;
	float dens = disc * (0.15 + arm * (1.1 + clump * 1.1)) * (1.0 - lane * 0.85) + bulge;
	vec3 col = mix(color_a.rgb, color_b.rgb, smoothstep(0.08, 0.4, r));
	float knots = smoothstep(0.58, 0.72, fbm(q * 16.0 + seed + 2.0)) * arm * smoothstep(0.15, 0.3, r) * disc;
	col = mix(col, color_d.rgb, clamp(knots * 3.0, 0.0, 1.0));
	col = mix(col, color_c.rgb, clamp(bulge, 0.0, 1.0));
	dens += knots * 1.6;
	float st = points(q * 45.0, 0.45) * arm * disc * stars * 3.0;
	vec4 g = vec4(col + color_b.rgb * st, dens + st);
	// Satellite dwarf galaxies.
	if (satellites > 0.0) {
		for (int k = 0; k < 2; k++) {
			vec2 c = k == 0 ? vec2(-0.55, -0.42) : vec2(0.48, 0.5);
			vec2 e = (p - c) * vec2(1.0, 2.2);
			float s = exp(-dot(e, e) * 260.0) * satellites * 1.3;
			g.rgb = mix(g.rgb, color_c.rgb, clamp(s / max(g.a + s, 1e-3), 0.0, 1.0));
			g.a += s;
		}
	}
	return g;
}

// Twin jets along the object's axis (pulsar wind, bipolar outflows).
vec4 jets_at(vec2 p) {
	float along = abs(p.x);
	float perp = abs(p.y);
	float wj = 0.05 * (1.0 - smoothstep(0.1, 0.85, along)) + 0.004;
	float j = exp(-perp * perp / (wj * wj)) * smoothstep(0.88, 0.3, along) * smoothstep(0.08, 0.25, along);
	j *= 0.6 + 0.7 * fbm(vec2(along * 12.0 - seed, perp * 40.0));
	return vec4(color_a.rgb, j * jets * 1.6);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = rot + TIME * drift;       // drift: a slow turn
	float c = cos(a), s = sin(a);
	p = vec2(c * p.x - s * p.y, s * p.x + c * p.y) / stretch;
	vec4 v;
	if (mode == 0) v = remnant(p);
	else if (mode == 1) v = planetary(p);
	else if (mode == 2) v = emission(p);
	else v = galaxy(p);
	// Features every kind can have.
	if (jets > 0.0) {
		vec4 j = jets_at(p);
		v.rgb = mix(v.rgb, j.rgb, clamp(j.a / max(v.a + j.a, 1e-3), 0.0, 1.0));
		v.a += j.a;
	}
	if (stars > 0.0 && mode < 2) {
		float st = points(p * 14.0, 0.2) * stars * smoothstep(1.0, 0.5, length(p));
		v.rgb = mix(v.rgb, color_c.rgb, clamp(st / max(v.a + st, 1e-3), 0.0, 1.0));
		v.a += st;
	}
	vec2 e = abs(UV * 2.0 - 1.0);
	float edge = smoothstep(1.0, 0.82, max(e.x, e.y));
	float dens = clamp(v.a, 0.0, 3.0) * edge;
	COLOR = vec4(v.rgb * dens * intensity, 1.0);
}
