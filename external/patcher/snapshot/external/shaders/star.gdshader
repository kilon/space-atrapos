// A procedural star (on a square ColorRect), modelled on the reference suns
// in external/images/star_refs/: boiling granulation and stringy filaments,
// bright active regions and dark spots, turbulent bands (brown dwarfs), a
// limb, flaring prominences, corona rays and a wide glow; neutron stars add
// magnetic field loops (dipole lines) and twin beams. Parameters come from
// StarGen (scripts/star_gen.gd), which mixes the templates per star.
shader_type canvas_item;
render_mode blend_premul_alpha;

#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/noise3.gdshaderinc"

uniform float disc = 0.3;          // disc radius as a fraction of the rect half-size
uniform float seed = 0.0;
uniform float spin = 0.02;
uniform float tilt = 0.2;
uniform int detail = 6;

// Surface
uniform vec4 c_dark : source_color = vec4(0.55, 0.2, 0.02, 1.0);
uniform vec4 c_mid : source_color = vec4(1.0, 0.55, 0.08, 1.0);
uniform vec4 c_hot : source_color = vec4(1.0, 0.92, 0.6, 1.0);
uniform float gran_scale = 5.0;
uniform float contrast = 1.0;
uniform float filaments = 0.35;    // stringy bright / dark lanes
uniform float active = 0.6;        // bright active regions
uniform float spots = 0.2;         // dark spots
uniform float banded = 0.0;        // brown-dwarf bands
uniform float band_count = 8.0;
uniform float limb = 0.4;          // limb darkening (negative: brighter rim)

// Around it
uniform vec4 c_corona : source_color = vec4(1.0, 0.7, 0.25, 1.0);
uniform float corona = 0.8;
uniform float glow = 0.8;
uniform float glow_size = 1.0;
uniform float prominences = 0.5;
uniform float prom_size = 1.0;

// Neutron stars
uniform float loops = 0.0;
uniform float loop_density = 1.0;
uniform float loop_extent = 5.0;   // in disc radii
uniform vec4 loop_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform vec4 loop_color2 : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float axis = 0.6;          // magnetic axis angle (rad)
uniform float beam = 0.0;
uniform float beam_width = 0.12;
uniform float beam_wobble = 0.0;   // precession (rad)
uniform vec4 beam_color : source_color = vec4(0.75, 0.88, 1.0, 1.0);

vec3 spun(vec3 b, float speed) {
	float a = TIME * speed;
	float c = cos(a), s = sin(a);
	return vec3(c * b.x - s * b.z, b.y, s * b.x + c * b.z);
}

vec3 surface(vec2 pd, float z) {
	float c = cos(tilt), s = sin(tilt);
	vec3 n = vec3(c * pd.x - s * pd.y, s * pd.x + c * pd.y, z);
	vec3 b = spun(n, spin);
	vec3 so = vec3(seed * 1.3, seed * 0.7, seed * 2.1);
	vec3 boil = vec3(0.0, TIME * 0.025, TIME * 0.02);
	vec3 q = b * gran_scale + so;
	q += 0.6 * (vec3(fbm3(q * 0.5 + 3.0, 3), fbm3(q * 0.5 + 7.0, 3), fbm3(q * 0.5 + 1.0, 3)) - 0.5);
	float g = fbm3(q + boil, detail);
	float f = ridged3(q * 1.6 - boil * 1.3 + 9.0, max(detail - 1, 3));
	float v = mix(g, g * 0.4 + f * 0.75, filaments);
	if (banded > 0.0) {
		vec3 tq = b * vec3(3.0, 9.0, 3.0) + so + boil;
		float w1 = fbm3(tq, 4);
		float w2 = fbm3(tq + vec3(w1 * 4.0, 0.0, w1 * 3.0), detail);
		float lat = b.y + 0.12 * (w2 - 0.5);
		float bands = 0.5 + 0.5 * sin(lat * band_count * 3.14159 + seed);
		float cracks = pow(1.0 - abs(w2 * 2.0 - 1.0), 6.0);
		float bv = bands * 0.55 + cracks * 0.6 + (fbm3(b * vec3(2.0, 30.0, 2.0) + so + w1, 4) - 0.5) * 0.4;
		v = mix(v, bv, banded);
	}
	v = clamp((v - 0.5) * contrast + 0.5, 0.0, 1.0);
	vec3 col = v < 0.5 ? mix(c_dark.rgb, c_mid.rgb, v * 2.0) : mix(c_mid.rgb, c_hot.rgb, (v - 0.5) * 2.0);
	if (active > 0.0) {
		float a = smoothstep(0.6, 0.78, fbm3(b * 1.6 + so + 4.0, 3));
		float sparks = pow(ridged3(b * gran_scale * 3.0 + so - boil * 2.0, 3), 3.0);
		col = mix(col, c_hot.rgb * 1.25, a * active * (0.35 + sparks * 0.9));
	}
	if (spots > 0.0) {
		float sp = smoothstep(0.68, 0.76, fbm3(b * 2.2 + so + 11.0, 4));
		col = mix(col, c_dark.rgb * 0.4, sp * spots);
	}
	return col;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float d = r / disc;
	vec2 pd = uv / disc;
	float fade = smoothstep(1.0, 0.7, r);    // nothing reaches the rect's edge
	vec3 add = vec3(0.0);                     // light (additive)
	// Wide glow and corona with rays.
	float ang = atan(uv.y, uv.x);
	float h = max(d - 1.0, 0.0);
	float outside = smoothstep(0.97, 1.0, d);
	add += c_corona.rgb * glow * exp(-h * 2.6 / glow_size) * 0.55 * outside;
	add += c_corona.rgb * glow * 0.25 * exp(-r * 2.5) * outside;
	float rays = fbm(vec2(ang * 3.0 + seed, TIME * 0.12)) * 0.6 + fbm(vec2(ang * 11.0 - seed, TIME * 0.25)) * 0.4;
	add += mix(c_corona.rgb, c_hot.rgb, 0.3) * corona * exp(-h * (7.0 - rays * 5.0)) * outside * 0.8;
	// Prominences: flaming filaments rising from the limb.
	if (prominences > 0.0 && d > 0.98) {
		float hp = h / (0.35 * prom_size);
		float site = smoothstep(0.45, 0.7, fbm(vec2(ang * 3.5 + seed * 2.0, TIME * 0.03)));
		float wob = fbm(vec2(ang * 14.0 + seed, hp * 2.0 - TIME * 0.2));
		float fib = 1.0 - abs(fbm(vec2(ang * 42.0 + wob * 6.0, hp * 3.5 - TIME * 0.35)) * 2.0 - 1.0);
		float pi = pow(fib, 5.0) * exp(-hp * 2.2) * (0.35 + site * 1.4);
		add += mix(c_mid.rgb, c_hot.rgb, exp(-hp * 3.0)) * pi * prominences * 1.6;
	}
	// Magnetic field loops: dipole lines r = L sin^2(theta) about the axis,
	// three families seen at different angles (x squeezed).
	if (loops > 0.0 && d > 1.0) {
		float ca = cos(axis), sa = sin(axis);
		vec2 m = vec2(ca * pd.x + sa * pd.y, -sa * pd.x + ca * pd.y);   // m.y along the axis
		float lsum = 0.0;
		float tw = 0.0;
		for (int k = 0; k < 3; k++) {
			float sq = 1.0 - float(k) * 0.33;
			vec2 mk = vec2(m.x / sq, m.y);
			float rk = length(mk);
			float s2 = (mk.x * mk.x) / max(rk * rk, 1e-4);
			float L = rk / max(s2, 1e-3);
			if (L > loop_extent * 1.4) continue;
			float u = log(L) * 3.2 * loop_density + float(k) * 0.37 + seed;
			u += 0.25 * fbm(vec2(atan(mk.y, mk.x) * 2.0 + float(k) * 5.0, u * 0.3 + seed));
			float dl = abs(fract(u) - 0.5);
			float line = smoothstep(0.455, 0.5, dl) + 0.25 * smoothstep(0.35, 0.5, dl);
			float flick = 0.55 + 0.6 * fbm(vec2(u * 2.0 + float(k), rk * 2.0 - TIME * 0.5));
			float w = exp(-max(L - 1.0, 0.0) / loop_extent) * (1.0 - float(k) * 0.25) * smoothstep(loop_extent * 1.4, loop_extent * 0.9, L);
			lsum += line * flick * w;
			tw += w * (k == 1 ? 1.0 : 0.0);
		}
		vec3 lc = mix(loop_color.rgb, loop_color2.rgb, clamp(tw, 0.0, 1.0));
		add += lc * lsum * loops * 1.1 * smoothstep(1.0, 1.25, d);
	}
	// Twin beams along the magnetic axis.
	if (beam > 0.0) {
		float ba = axis + sin(TIME * 0.7 + seed) * beam_wobble;
		vec2 dir = vec2(-sin(ba), cos(ba));
		float along = abs(dot(pd, dir));
		float perp = abs(dot(pd, vec2(dir.y, -dir.x)));
		float w = beam_width * (0.6 + along * 0.22);
		float streak = 0.6 + 0.7 * fbm(vec2(perp / w * 3.0 + seed, along * 1.5 - TIME * 3.0));
		float bi = exp(-perp * perp / (w * w)) * streak * smoothstep(0.9, 1.3, d);
		add += mix(beam_color.rgb, vec3(1.0), exp(-perp * perp / (w * w * 0.1)) * 0.6) * bi * beam * 1.5;
	}
	add *= fade;
	vec4 outc = vec4(add, clamp(max(add.r, max(add.g, add.b)) * 0.25, 0.0, 1.0));
	if (d < 1.0) {
		float z = sqrt(1.0 - d * d);
		vec3 col = surface(pd, z);
		col *= 1.0 - limb + limb * pow(z, 0.5);
		if (limb < 0.0) col += c_hot.rgb * pow(1.0 - z, 3.0) * -limb * 2.0;
		col += c_hot.rgb * pow(z, 8.0) * 0.12;
		float edge = smoothstep(1.0, 0.985, d);
		outc = vec4(col * edge + outc.rgb * (1.0 - edge * 0.85), max(edge, outc.a));
	}
	COLOR = outc;
}
