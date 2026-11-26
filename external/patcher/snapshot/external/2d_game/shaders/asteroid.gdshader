// Procedural asteroid: a ray-marched 3D rock on a quad, slowly tumbling, lit
// from a fixed screen direction. Modelled on external/images/asteroid_refs/:
// a contact binary (two fused lobes, crisp craters) and a craggy, elongated
// rock (deep pits, ridges, rust-orange patches). The body is a smooth union
// of two ellipsoids, displaced by lumps, ridged crags and crater bowls; fine
// craters and pitting only bend the normal. Ore veins glow on the surface.
// The lock-on outline is drawn here too, hugging the silhouette.
shader_type canvas_item;

#include "res://shaders/noise3.gdshaderinc"

// --- Shape ---
uniform float seed = 0.0;
uniform float fit = 0.8;            // body units -> quad units (set by AsteroidGen)
uniform float elongation = 1.3;     // stretch of the long axis
uniform float flatten = 0.85;       // squash of the short axis
uniform float binary = 0.0;         // 0 = one body, 1 = two fused lobes
uniform float lobe_ratio = 0.8;     // second lobe's size
uniform float neck = 0.25;          // how smoothly the lobes merge
uniform float lumps = 0.5;
uniform float lump_scale = 1.6;
uniform float crags = 0.3;          // ridged, broken relief
uniform float craters = 0.6;
uniform float crater_scale = 2.2;
uniform float crater_depth = 1.0;
uniform float small_craters = 0.6;
uniform float pitting = 0.5;
uniform int detail = 4;
// --- Motion ---
uniform vec3 pose = vec3(0.3, 0.8, 0.2);   // initial orientation (euler, rad)
uniform float spin = 0.12;          // rad/s
uniform float tumble = 0.35;        // tilt of the spin axis out of the screen plane
uniform float time_offset = 0.0;
// --- Colour ---
uniform vec4 c_rock : source_color = vec4(0.42, 0.4, 0.38, 1.0);
uniform vec4 c_dark : source_color = vec4(0.16, 0.14, 0.13, 1.0);
uniform vec4 c_light : source_color = vec4(0.72, 0.7, 0.66, 1.0);
uniform vec4 c_rust : source_color = vec4(0.62, 0.4, 0.24, 1.0);
uniform float rust = 0.4;
uniform float rust_scale = 2.0;
uniform float cavity_rust = 0.5;    // rust gathered in pits and crater floors
uniform float dust = 0.3;           // pale dust on the crests
uniform float color_noise = 0.3;
// --- Light ---
uniform vec2 light = vec2(-0.6, -0.5);   // screen direction the light comes from
uniform vec4 light_color : source_color = vec4(1.0, 0.95, 0.88, 1.0);
uniform float ambient = 0.1;
uniform float contrast = 1.1;
uniform float rim = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0, 0.7, 0.45, 1.0);
uniform float specular = 0.15;
// --- Ore veins ---
uniform float veins = 0.0;
uniform float vein_scale = 2.5;
uniform float vein_width = 0.08;
uniform vec4 vein_color : source_color = vec4(0.4, 0.9, 1.0, 1.0);
uniform float vein_glow = 0.0;
// --- Lock-on (set by the game) ---
uniform float outline = 0.0;
uniform vec4 outline_color : source_color = vec4(1.0, 0.12, 0.08, 1.0);

varying vec2 q;

vec3 hash33(vec3 p) {
	return vec3(hash31(p), hash31(p + vec3(37.0, 11.0, 5.0)), hash31(p + vec3(3.0, 71.0, 29.0)));
}

mat3 rot_x(float a) { float c = cos(a), s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_y(float a) { float c = cos(a), s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }
mat3 rot_z(float a) { float c = cos(a), s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }

// Crater bowls with raised rims; only the 8 nearest cells can reach p.
float crater_field(vec3 p, float density) {
	vec3 c0 = floor(p - 0.5);
	float h = 0.0;
	float rims = 0.0;
	for (int i = 0; i < 8; i++) {
		vec3 c = c0 + vec3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1));
		vec3 r = hash33(c + seed);
		if (r.x > density) continue;
		vec3 centre = c + 0.3 + 0.4 * hash33(c + 17.0 + seed);
		float rad = 0.16 + 0.19 * r.y;
		float d = length(p - centre) / rad;
		if (d > 1.6) continue;
		float bowl = d < 1.0 ? (d * d - 1.0) * rad : 0.0;
		float rm = 0.3 * rad * exp(-(d - 1.0) * (d - 1.0) * 14.0);
		h = min(h, bowl);
		rims = max(rims, rm);
	}
	return h + rims;
}

float sd_ellipsoid(vec3 p, vec3 r) {
	float k0 = length(p / r);
	float k1 = length(p / (r * r));
	return k0 * (k0 - 1.0) / max(k1, 1e-4);
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// The base body (lobes) in body units.
float base_shape(vec3 p) {
	float sep = binary * 0.62;
	vec3 r1 = vec3(elongation * mix(1.0, 0.72, binary), 1.0, flatten);
	float d = sd_ellipsoid(p + vec3(sep, 0.0, 0.0), r1);
	if (binary > 0.01) {
		vec3 r2 = r1 * lobe_ratio;
		d = smin(d, sd_ellipsoid(p - vec3(sep * lobe_ratio + 0.05, 0.08, 0.0), r2), max(neck, 0.02));
	}
	return d;
}

// Relief: positive = outward. `fine` adds what only shades (not the outline).
float relief(vec3 p, bool fine) {
	vec3 s = p + seed * 1.37;
	float h = lumps * 0.32 * (fbm3(s * lump_scale, 3) - 0.5);
	h += crags * 0.22 * (ridged3(s * lump_scale * 1.7 + 4.0, fine ? 3 : 2) - 0.45);
	h += craters * crater_depth * 0.5 * crater_field(p * crater_scale, 0.5) / crater_scale;
	if (fine) {
		h += small_craters * crater_depth * 0.5 * crater_field(p * crater_scale * 3.3 + 9.0, 0.6) / (crater_scale * 3.3);
		h -= pitting * 0.018 * smoothstep(0.55, 0.85, vnoise3(s * 34.0));
		h += pitting * 0.012 * (fbm3(s * 14.0, max(detail - 2, 1)) - 0.5);
	}
	return h;
}

float sdf(vec3 p, bool fine) {
	return (base_shape(p) - relief(p, fine)) * 0.75;
}

void vertex() {
	q = UV * 2.0 - 1.0;
}

void fragment() {
	float t = TIME + time_offset;
	// View -> body: the pose, then a spin about an axis tilted out of the screen.
	mat3 spin_m = rot_x(tumble) * rot_z(spin * t) * rot_x(-tumble);
	mat3 body = rot_z(pose.z) * rot_y(pose.y) * rot_x(pose.x) * spin_m;
	mat3 to_view = transpose(body);
	vec2 sp = q / fit;                       // screen point in body units
	vec3 ro = vec3(sp, 3.0);
	vec3 rd = vec3(0.0, 0.0, -1.0);
	float px = fwidth(q.x) / fit;            // one pixel in body units
	float bound = elongation + binary * 0.9 + 0.5;
	float tt = 0.0;
	float min_d = 1e3;
	bool hit = false;
	vec3 pv = ro;
	if (length(sp) < bound) {
		tt = 3.0 - bound;
		for (int i = 0; i < 64; i++) {
			pv = ro + rd * tt;
			float d = sdf(body * pv, false);
			min_d = min(min_d, d);
			if (d < 0.0015) { hit = true; break; }
			tt += max(d, 0.004);
			if (tt > 3.0 + bound) break;
		}
	}
	vec4 col = vec4(0.0);
	if (hit) {
		vec3 po = body * pv;
		// Normal (tetrahedral differences of the detailed surface), in view space.
		float e = 0.006;
		vec2 k = vec2(1.0, -1.0);
		vec3 n = normalize(k.xyy * sdf(body * (pv + k.xyy * e), true) + k.yyx * sdf(body * (pv + k.yyx * e), true)
			+ k.yxy * sdf(body * (pv + k.yxy * e), true) + k.xxx * sdf(body * (pv + k.xxx * e), true));
		// Cavities: how far the detailed surface sinks below the smooth one.
		float ao = clamp(sdf(body * (pv + n * 0.09), true) / 0.09, 0.0, 1.0);
		float cav = clamp(0.5 - (relief(po, true) - relief(po, false)) * 22.0, 0.0, 1.0);
		float crest = clamp(relief(po, true) * 4.0 + 0.5, 0.0, 1.0);
		// Albedo.
		vec3 s = po + seed * 2.11;
		float cn = fbm3(s * 3.0, 3);
		vec3 alb = c_rock.rgb * (1.0 + color_noise * (cn - 0.5) * 1.6);
		alb = mix(alb, c_dark.rgb, (1.0 - ao) * 0.6);
		float r_mask = smoothstep(0.56, 0.76, fbm3(s * rust_scale + 3.0, 4)) * rust;
		r_mask = max(r_mask, cavity_rust * smoothstep(0.35, 0.85, cav) * smoothstep(0.35, 0.6, fbm3(s * rust_scale * 1.8, 3)));
		alb = mix(alb, c_rust.rgb * (0.8 + 0.4 * cn), clamp(r_mask, 0.0, 1.0));
		alb = mix(alb, c_light.rgb, dust * smoothstep(0.55, 0.9, crest) * smoothstep(0.4, 0.7, vnoise3(s * 9.0)));
		// Veins of ore: thin seams along a ridged pattern.
		float vein = 0.0;
		if (veins > 0.0) {
			float v = 1.0 - abs(vnoise3(s * vein_scale + 21.0) * 2.0 - 1.0);
			v = max(v, (1.0 - abs(vnoise3(s * vein_scale * 2.3 + 5.0) * 2.0 - 1.0)) * smoothstep(0.5, 0.6, vnoise3(s * 2.0 + 3.0)));
			vein = smoothstep(1.0 - vein_width, 1.0 - vein_width * 0.25, v) * smoothstep(0.42, 0.56, fbm3(s * 1.3 + 8.0, 2)) * veins;
			alb = mix(alb, vein_color.rgb, clamp(vein, 0.0, 1.0) * 0.8);
		}
		// Lighting (fixed screen light, so it stays put while the rock turns).
		vec3 L = normalize(vec3(light.x, light.y, 0.7));
		float diff = max(dot(n, L), 0.0);
		diff = pow(diff, contrast);
		vec3 lit = alb * (ambient + diff * light_color.rgb * 1.55) * mix(0.4, 1.0, ao);
		vec3 h = normalize(L + vec3(0.0, 0.0, 1.0));
		lit += light_color.rgb * specular * pow(max(dot(n, h), 0.0), 24.0) * ao;
		float fres = pow(1.0 - max(n.z, 0.0), 3.0);
		lit += rim_color.rgb * rim * fres * (0.35 + 0.65 * max(dot(normalize(vec3(n.xy, 0.0)), normalize(vec3(light, 0.0))), 0.0));
		lit += vein_color.rgb * vein * vein_glow * 0.6 * (0.8 + 0.2 * sin(t * 2.5 + seed));
		col = vec4(lit, 1.0);
	} else if (min_d < px * 1.5 && min_d < 1e2) {
		col = vec4(c_dark.rgb * 0.5, 1.0 - min_d / (px * 1.5));   // soft edge
	}
	// Lock-on: a pulsing glow hugging the outline, with dashes running round.
	if (outline > 0.0 && !hit && min_d < 1e2) {
		float pulse = 0.72 + 0.28 * sin(t * 6.0);
		float w = 0.035 / fit;
		float glow = exp(-max(min_d, 0.0) / w) * pulse;
		float line = smoothstep(px * 2.0, 0.0, abs(min_d - 0.025 / fit));
		float ang = atan(sp.y, sp.x);
		float dash = step(0.65, fract(ang * 8.0 / 6.2832 - t * 0.6));
		vec3 oc = mix(outline_color.rgb, vec3(1.0, 0.85, 0.75), dash * line);
		float a = clamp(glow * 0.6 + line * pulse, 0.0, 1.0) * outline;
		col = vec4(mix(col.rgb, oc, a), max(col.a, a));
	}
	COLOR = col * COLOR;
}
