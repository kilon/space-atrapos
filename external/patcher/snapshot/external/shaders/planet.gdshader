// Procedural planet (on a square ColorRect), modelled on the reference
// planets in external/images/planet_refs/: rocky worlds (ridged mountains,
// seas that can glow, ice and snow, lava cracks, craters, alien biome
// patches, clouds with a cyclone) and gas giants (turbulent bands, a great
// storm, rings). The surface is 3D noise on a spinning, tilted sphere, lit
// from light_dir with relief from the terrain. Every parameter comes from
// PlanetGen (scripts/planet_gen.gd), which mixes the templates so that no two
// planets look alike.
shader_type canvas_item;
render_mode blend_premul_alpha;

// --- Shape and view ---
uniform int mode = 0;                 // 0 rocky, 1 gas giant
uniform float planet_radius = 0.86;   // disk radius / half the rect
uniform float seed = 0.0;
uniform float spin = 0.01;            // rad / s
uniform float tilt = 0.3;             // axis tilt in the screen plane (rad)
uniform float incline = 0.35;         // how far we look down on the equator (rad)
uniform vec3 light_dir = vec3(-0.6, -0.5, 0.65);   // x right, y down, z toward the viewer
uniform int detail = 6;               // noise octaves

// --- Rocky surface ---
uniform float terrain_scale = 2.2;
uniform float warp = 0.5;
uniform float ridges = 0.6;           // 0 rolling, 1 sharp mountain ranges
uniform float relief = 1.0;           // bump lighting strength
uniform vec4 land_low : source_color = vec4(0.35, 0.3, 0.22, 1.0);
uniform vec4 land_mid : source_color = vec4(0.5, 0.4, 0.3, 1.0);
uniform vec4 land_high : source_color = vec4(0.3, 0.28, 0.27, 1.0);
uniform vec4 land_peak : source_color = vec4(0.75, 0.73, 0.7, 1.0);
uniform float biome = 0.0;            // patches of a second ground colour
uniform float biome_scale = 1.6;
uniform vec4 biome_color : source_color = vec4(0.7, 0.35, 0.15, 1.0);
uniform float water_level = -1.0;     // -1: no water
uniform vec4 water_shallow : source_color = vec4(0.1, 0.5, 0.6, 1.0);
uniform vec4 water_deep : source_color = vec4(0.02, 0.1, 0.25, 1.0);
uniform float water_glow = 0.0;       // glowing shallows
uniform float ice_cover = 0.0;        // snow on heights + polar caps
uniform vec4 ice_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float craters = 0.0;
uniform float crater_scale = 3.0;
uniform float lava = 0.0;
uniform float lava_scale = 2.5;
uniform vec4 lava_color : source_color = vec4(1.0, 0.3, 0.05, 1.0);
uniform vec4 lava_hot : source_color = vec4(1.0, 0.85, 0.35, 1.0);
uniform float clouds = 0.0;           // coverage
uniform float cloud_scale = 2.5;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float cyclone = 0.0;
uniform vec3 cyclone_dir = vec3(0.4, 0.3, 0.86);

// --- Gas giant ---
uniform float band_count = 7.0;
uniform float band_turb = 0.5;
uniform vec4 gas_a : source_color = vec4(0.85, 0.75, 0.6, 1.0);
uniform vec4 gas_b : source_color = vec4(0.6, 0.45, 0.3, 1.0);
uniform vec4 gas_c : source_color = vec4(0.95, 0.9, 0.8, 1.0);
uniform vec4 gas_d : source_color = vec4(0.4, 0.5, 0.65, 1.0);
uniform float storm = 0.0;
uniform vec2 storm_pos = vec2(0.6, -0.35);   // longitude, latitude (rad)
uniform float storm_size = 0.18;
uniform vec4 storm_color : source_color = vec4(0.85, 0.4, 0.15, 1.0);

// --- Rings ---
uniform float rings = 0.0;
uniform float ring_inner = 1.35;
uniform float ring_outer = 2.25;
uniform vec4 ring_a : source_color = vec4(0.85, 0.78, 0.65, 1.0);
uniform vec4 ring_b : source_color = vec4(0.55, 0.5, 0.45, 1.0);

// --- Atmosphere ---
uniform vec4 atmosphere : source_color = vec4(0.45, 0.7, 1.0, 1.0);
uniform float atmo_strength = 0.6;

#include "res://shaders/noise3.gdshaderinc"

vec3 hash33(vec3 p) {
	return vec3(hash31(p), hash31(p + vec3(37.0, 11.0, 5.0)), hash31(p + vec3(3.0, 71.0, 29.0)));
}

// Crater field: bowls with raised rims (height offset).
float crater_field(vec3 p) {
	vec3 c0 = floor(p);
	float h = 0.0;
	float rims = 0.0;
	for (int x = -1; x <= 1; x++)
	for (int y = -1; y <= 1; y++)
	for (int z = -1; z <= 1; z++) {
		vec3 c = c0 + vec3(float(x), float(y), float(z));
		vec3 r = hash33(c);
		if (r.x > 0.55) continue;
		vec3 centre = c + 0.2 + 0.6 * hash33(c + 17.0);
		float rad = 0.22 + 0.3 * r.y;
		float d = length(p - centre) / rad;
		if (d > 1.6) continue;
		float bowl = d < 1.0 ? (d * d - 1.0) * 0.55 : 0.0;
		float rim = 0.28 * exp(-(d - 1.0) * (d - 1.0) * 18.0);
		h = min(h, bowl);
		rims = max(rims, rim);
	}
	return h + rims;
}

vec3 grad4(vec3 a, vec3 b, vec3 c, vec3 d, float t) {
	if (t < 0.33) return mix(a, b, t / 0.33);
	if (t < 0.7) return mix(b, c, (t - 0.33) / 0.37);
	return mix(c, d, (t - 0.7) / 0.3);
}

// Screen space (x right, y down, z toward the viewer) -> the planet's frame:
// y = its axis, rings lie in y = 0.
vec3 to_body(vec3 v) {
	float c = cos(tilt), s = sin(tilt);
	vec3 u = vec3(c * v.x - s * v.y, s * v.x + c * v.y, v.z);
	float ci = cos(incline), si = sin(incline);
	return vec3(u.x, u.y * ci - u.z * si, u.y * si + u.z * ci);
}

vec3 spun(vec3 b, float speed) {
	float a = TIME * speed;
	float c = cos(a), s = sin(a);
	return vec3(c * b.x - s * b.z, b.y, s * b.x + c * b.z);
}

vec3 rotate_about(vec3 v, vec3 k, float a) {
	return v * cos(a) + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - cos(a));
}

vec3 warped(vec3 bs) {
	vec3 so = vec3(seed * 1.31, seed * 0.71, seed * 2.13);
	vec3 q = bs * terrain_scale + so;
	vec3 w = vec3(fbm3(q * 0.6 + vec3(5.2, 1.3, 8.1), 3), fbm3(q * 0.6 + vec3(1.7, 9.2, 3.4), 3),
		fbm3(q * 0.6 + vec3(8.3, 2.8, 6.1), 3)) - 0.5;
	return q + warp * w * 2.4;
}

// Terrain height at body point bs (q = its warped noise coordinate).
float height_at(vec3 bs, vec3 q) {
	vec3 so = vec3(seed * 1.31, seed * 0.71, seed * 2.13);
	float base = fbm3(q, detail);
	float rd = ridged3(q * 1.4 + 3.1, max(detail - 1, 2));
	float h = mix(base, base * 0.5 + rd * 0.62, ridges);
	h = (h - 0.5) * 2.0 + 0.5;
	if (craters > 0.0) {
		h += craters * 0.35 * crater_field(bs * crater_scale + so);
		h += craters * 0.18 * crater_field(bs * crater_scale * 3.1 + so * 1.7);
	}
	return h;
}

// Rocky surface: colour, emission, height (for relief) and wetness (specular).
void rocky(vec3 b, vec3 bs, out vec3 col, out vec3 emit, out float h, out float wet, out float hw) {
	vec3 so = vec3(seed * 1.31, seed * 0.71, seed * 2.13);
	h = height_at(bs, warped(bs));
	hw = 0.0;
	emit = vec3(0.0);
	wet = 0.0;
	float wl = water_level;
	float hl = wl > -0.5 ? clamp((h - wl) / max(0.95 - wl, 0.1), 0.0, 1.0) : clamp((h - 0.1) / 0.8, 0.0, 1.0);
	float n2 = fbm3(bs * 9.0 + so + 4.0, 3);
	col = grad4(land_low.rgb, land_mid.rgb, land_high.rgb, land_peak.rgb, clamp(hl + (n2 - 0.5) * 0.18, 0.0, 1.0));
	// Fine grain / strata.
	col *= 0.86 + 0.28 * fbm3(bs * 26.0 + so, 3);
	if (biome > 0.0) {
		float bp = smoothstep(0.47, 0.56, fbm3(bs * biome_scale + so + 9.0, 4));
		col = mix(col, biome_color.rgb * (0.75 + 0.5 * n2), bp * biome * (1.0 - hl * 0.5));
	}
	if (lava > 0.0) {
		float lr = 1.0 - abs(fbm3(bs * lava_scale + so + 2.0, 5) * 2.0 - 1.0);
		float crack = smoothstep(0.93, 0.99, lr) * (1.0 - hl * 0.6);
		float pool = smoothstep(0.08, 0.0, hl) * 0.8;
		float m = clamp(max(crack, pool), 0.0, 1.0) * lava;
		col = mix(col, col * 0.55 + lava_color.rgb * 0.25, smoothstep(0.7, 0.9, lr) * lava * 0.6);
		col = mix(col, lava_color.rgb * 0.4, m);
		emit += mix(lava_color.rgb, lava_hot.rgb, m * m) * m * 1.5;
	}
	float lat = abs(b.y);
	float hc = h + (fbm3(bs * 34.0 + so, 3) - 0.5) * 0.07;   // ragged coasts
	if (wl > -0.5 && hc < wl) {
		float d = clamp((wl - hc) / 0.3, 0.0, 1.0);
		vec3 wc = mix(water_shallow.rgb, water_deep.rgb, smoothstep(0.0, 1.0, d));
		wc *= 0.9 + 0.2 * fbm3(bs * 14.0 + so, 3);
		emit += water_shallow.rgb * water_glow * pow(1.0 - d, 2.5) * 1.4;
		col = wc;
		wet = 1.0;
	}
	if (ice_cover > 0.0) {
		float snow = smoothstep(0.0, 0.12, hl - (1.0 - ice_cover) + (n2 - 0.5) * 0.3);
		float polar = smoothstep(0.0, 0.08, lat - (1.0 - ice_cover * 0.75) + (n2 - 0.5) * 0.25);
		float ice = max(snow * (wet > 0.5 ? 0.0 : 1.0), polar);
		vec3 ic = ice_color.rgb * (0.82 + 0.25 * fbm3(bs * 18.0 + so, 3));
		col = mix(col, ic, clamp(ice, 0.0, 1.0));
		wet *= 1.0 - polar;
	}
}

void clouds_at(vec3 b, out float c) {
	vec3 cb = spun(b, spin * 1.35);
	if (cyclone > 0.0) {
		vec3 cd = normalize(cyclone_dir);
		float ang = acos(clamp(dot(cb, cd), -1.0, 1.0));
		float r = 0.55;
		if (ang < r) {
			float k = 1.0 - ang / r;
			cb = rotate_about(cb, cd, cyclone * 7.0 * k * k);
		}
	}
	vec3 cq = cb * cloud_scale * vec3(1.0, 1.7, 1.0) + vec3(seed * 0.37, 2.0, seed);
	cq += 0.8 * (vec3(fbm3(cq * 0.8, 3), fbm3(cq * 0.8 + 7.0, 3), fbm3(cq * 0.8 + 3.0, 3)) - 0.5);
	float d = fbm3(cq, detail);
	float thr = mix(0.72, 0.38, clouds);
	c = smoothstep(thr, thr + 0.22, d) * min(clouds * 3.0, 1.0);
	if (cyclone > 0.0) {
		float ang = acos(clamp(dot(cb, normalize(cyclone_dir)), -1.0, 1.0));
		c = max(c, cyclone * smoothstep(0.5, 0.1, ang) * smoothstep(0.42, 0.6, d));
		c *= smoothstep(0.015, 0.05, ang);
	}
}

vec3 gas(vec3 b) {
	vec3 g = spun(b, spin);
	vec3 so = vec3(seed * 0.9, seed * 0.3, seed * 1.3);
	float lat = g.y;
	// Turbulence: twice-warped noise stretched along the bands.
	vec3 tq = g * vec3(3.0, 9.0, 3.0) + so;
	float w1 = fbm3(tq, 4);
	float w2 = fbm3(tq + vec3(w1 * 4.0, 0.0, w1 * 3.0), detail);
	float lat2 = lat + band_turb * 0.14 * (w2 - 0.5);
	float lon = atan(g.z, g.x);
	float glat = asin(clamp(lat, -1.0, 1.0));
	float sd = 99.0;
	float sang = 0.0;
	vec2 er = vec2(0.0);
	if (storm > 0.0) {
		float dl = mod(lon - storm_pos.x + PI, TAU) - PI;
		vec2 e = vec2(dl * cos(glat) * 0.55, glat - storm_pos.y);
		sd = length(e) / storm_size;
		if (sd < 1.6) {
			float k = max(1.0 - sd / 1.6, 0.0);
			sang = storm * 5.0 * k * k;
			er = mat2(vec2(cos(sang), sin(sang)), vec2(-sin(sang), cos(sang))) * e;
			lat2 = sin(storm_pos.y + er.y) + band_turb * 0.1 * (w2 - 0.5);
		}
	}
	float v = lat2 * band_count;
	float b1 = 0.5 + 0.5 * sin(v * PI + seed);
	float b2 = 0.5 + 0.5 * sin(v * 1.37 * PI + seed * 1.7);
	float fine = vnoise3(vec3(v * 5.0, seed, 0.0) + vec3(0.0, w1 * 2.0, 0.0));
	vec3 col = mix(gas_a.rgb, gas_b.rgb, smoothstep(0.15, 0.85, b1));
	col = mix(col, gas_c.rgb, smoothstep(0.55, 0.92, b2) * 0.85);
	col = mix(col, gas_d.rgb, smoothstep(0.55, 0.9, fine) * 0.65);
	col *= 0.86 + 0.28 * fbm3(g * vec3(2.0, 40.0, 2.0) + so + w2 * 2.0, 4);
	if (storm > 0.0 && sd < 1.2) {
		float sc = smoothstep(1.15, 0.35, sd);
		float sw = fbm3(vec3(er / storm_size * 2.2, seed + 5.0), 4);
		vec3 swirl = storm_color.rgb * (0.6 + 0.75 * sw);
		swirl = mix(swirl, gas_c.rgb, smoothstep(0.62, 0.8, sw) * 0.5);
		col = mix(col, swirl, sc * storm * 0.9);
	}
	return col;
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) / planet_radius;
	float r = length(p);
	float aa = fwidth(r) * 1.2;
	vec3 L = normalize(light_dir);
	vec4 out_col = vec4(0.0);   // premultiplied

	// Rings: the screen point on the ring plane, its radius and depth.
	vec4 ring_front = vec4(0.0);
	vec4 ring_back = vec4(0.0);
	if (rings > 0.0) {
		float c = cos(tilt), s = sin(tilt);
		vec2 u = vec2(c * p.x - s * p.y, s * p.x + c * p.y);
		float si = max(sin(incline), 0.05);
		float rr = length(vec2(u.x, u.y / si));
		float z = u.y * cos(incline) / si;
		if (rr > ring_inner && rr < ring_outer) {
			float t = (rr - ring_inner) / (ring_outer - ring_inner);
			float bands = 0.55 + 0.45 * vnoise3(vec3(rr * 38.0, seed, 0.0));
			bands *= 0.7 + 0.3 * vnoise3(vec3(rr * 140.0, seed + 3.0, 0.0));
			float gap = smoothstep(0.015, 0.0, abs(t - 0.62)) + smoothstep(0.01, 0.0, abs(t - 0.86)) * 0.7;
			float a = bands * (1.0 - gap) * smoothstep(0.0, 0.04, t) * smoothstep(1.0, 0.94, t) * rings;
			vec3 rc = mix(ring_b.rgb, ring_a.rgb, vnoise3(vec3(rr * 9.0, seed + 7.0, 0.0)));
			// The planet's shadow on the rings.
			vec3 R = vec3(p, z);
			float tc = -dot(R, L);
			float sh = (tc > 0.0 && length(R + tc * L) < 1.0) ? 0.18 : 1.0;
			rc *= sh * (0.75 + 0.35 * clamp(L.z + 0.4, 0.0, 1.0));
			vec4 rv = vec4(rc * a, a);
			if (z > 0.0) ring_front = rv; else ring_back = rv;
		}
	}

	out_col = ring_back;

	// Atmosphere halo beyond the disk.
	if (r > 1.0) {
		float halo = 0.09;
		float k = clamp(1.0 - (r - 1.0) / halo, 0.0, 1.0);
		float facing = clamp(dot(normalize(p), normalize(L.xy + vec2(1e-4))) * 0.6 + 0.55, 0.0, 1.0);
		float a = k * k * atmo_strength * 0.7 * facing;
		out_col = vec4(atmosphere.rgb * a, a) + out_col * (1.0 - a);
	}

	if (r < 1.0 + aa) {
		float zz = sqrt(max(1.0 - r * r, 0.0));
		vec3 n = vec3(p, zz);
		vec3 b = to_body(n);
		vec3 col;
		vec3 emit = vec3(0.0);
		float wet = 0.0;
		vec3 nn = n;
		if (mode == 1) {
			col = gas(b);
		} else {
			vec3 bs = spun(b, spin);
			float h, hw;
			rocky(b, bs, col, emit, h, wet, hw);
			if (wet < 0.5 && relief > 0.0) {
				// Relief: the height's slope along two surface tangents, from
				// samples a pixel or so away (the warp hardly changes there).
				float eps = max(abs(dFdx(p.x)), 1e-4) * 1.5;
				vec3 t1 = normalize(cross(vec3(0.0, 1.0, 0.0), n) + vec3(1e-4, 0.0, 0.0));
				vec3 t2 = cross(n, t1);
				vec3 d1 = spun(to_body(t1), spin) * eps;
				vec3 d2 = spun(to_body(t2), spin) * eps;
				vec3 q0 = warped(bs);
				float h1 = height_at(bs + d1, q0 + d1 * terrain_scale);
				float h2 = height_at(bs + d2, q0 + d2 * terrain_scale);
				vec2 gr = vec2(h1 - h, h2 - h) / eps;
				gr = clamp(gr, vec2(-10.0), vec2(10.0));
				nn = normalize(n - (t1 * gr.x + t2 * gr.y) * relief * 0.085);
				float slope = length(gr);
				col *= 1.0 - smoothstep(2.0, 7.0, slope) * 0.22 * ridges;
			}
		}
		float diff = dot(nn, L);
		float lit = smoothstep(-0.18, 0.55, diff);
		float limb = mix(0.55, 1.0, pow(zz, 0.4));
		vec3 shade = col * (0.05 + 0.95 * lit) * limb;
		if (wet > 0.0) {
			vec3 hv = normalize(L + vec3(0.0, 0.0, 1.0));
			shade += vec3(0.9, 0.95, 1.0) * pow(max(dot(n, hv), 0.0), 60.0) * 0.45 * wet;
		}
		if (mode == 0 && clouds > 0.0) {
			float c;
			clouds_at(b, c);
			float cl = smoothstep(-0.25, 0.6, dot(n, L));
			shade *= 1.0 - c * 0.35;
			shade = mix(shade, cloud_color.rgb * (0.08 + 0.92 * cl) * limb, c * cloud_color.a);
			emit *= 1.0 - c * 0.6;
		}
		shade += emit * (0.55 + 0.45 * (1.0 - lit));
		// Atmosphere rim.
		float fres = pow(1.0 - zz, 3.0) * atmo_strength;
		shade += atmosphere.rgb * fres * (0.15 + lit);
		float a = clamp((1.0 - r) / aa + 0.5, 0.0, 1.0);
		out_col = vec4(shade * a, a) + out_col * (1.0 - a);
	}

	out_col = ring_front + out_col * (1.0 - ring_front.a);
	COLOR = out_col;
}
