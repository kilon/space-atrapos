// The empires' looks (EmpireKit): ships' hulls, their insides, stations and
// their bays - one material for a whole model, each face's part of it by its
// vertex colour's red channel (zone = round(r * 16)):
//   0 main paint / stone   1 accent paint   2 dark iron   3 bright steel
//   4 a lamp   5 a screen (its UV a radar)   6 the roundel (UV: the disc - the
//   empire's emblem)   7 a banner (UV: the cloth - the emblem on it)
//   8 pale leather   9 accent cloth (green channel 1: a carpet's border)
//   10 leaves   11 hazard stripes   12 the frieze (UV: along, across; green
//   channel: its repeats / 40)   13 gold trim   14 the second accent
// The colours and the devices are the empire's (parameters: an empire a
// material): `emblem` 0 the Minoan triskelion (its banner: the bull's head),
// 1 Athens' owl, 2 Sparta's lambda, 3 Mycenae's rosette, 4 Ionia's lyre,
// 5 the Cyclades' spiral, 6 the Sea Peoples' skull, 7 a plain star;
// `frieze` 0 the running wave, 1 the meander, 2 lambdas, 3 rosettes,
// 4 spirals, 5 teeth.
// Painted metal or cut stone worn by use: seams on a grid (`blocks`: each
// block its own tone - masonry), `marble`: veins; grime, chips, streaks; less
// of it all inside (`wear`). Both sides drawn: a hull's inner face (seen
// through an open door, a window) is dark bare metal.
// `zone_override` >= 0: every face that zone (other builders' meshes, no colours).
shader_type spatial;
render_mode cull_disabled;

uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform vec3 cream : source_color = vec3(0.80, 0.74, 0.62);     // (the main colour)
uniform vec3 red : source_color = vec3(0.46, 0.08, 0.06);       // (the accent)
uniform vec3 accent2 : source_color = vec3(0.1, 0.35, 0.4);
uniform vec3 iron : source_color = vec3(0.20, 0.20, 0.21);
uniform vec3 steel : source_color = vec3(0.62, 0.61, 0.60);
uniform vec3 gold : source_color = vec3(0.83, 0.62, 0.22);
uniform vec3 amber : source_color = vec3(1.0, 0.58, 0.2);       // (the lamps)
uniform vec3 screen : source_color = vec3(0.25, 0.65, 1.0);
uniform vec3 emblem_ground : source_color = vec3(0.46, 0.08, 0.06);
uniform vec3 emblem_ink : source_color = vec3(0.80, 0.74, 0.62);
uniform vec3 frieze_ground : source_color = vec3(0.80, 0.74, 0.62);
uniform vec3 frieze_ink : source_color = vec3(0.46, 0.08, 0.06);
uniform int emblem = 0;
uniform int frieze = 0;
uniform float wear = 1.0;
uniform float inside = 0.0;         // (1: no mirror metal - nothing to mirror in a closed room)
uniform float zone_override = -1.0;
uniform float panel = 2.2;          // m between seams
uniform float blocks = 0.0;         // (masonry: each block its own tone, deeper joints)
uniform float marble = 0.0;         // (veined stone)
uniform float glow = 1.0;
uniform float flood = 0.0;          // (a station's emblems, friezes and banners floodlit: seen on its unlit sides too)

varying vec3 v_obj;
#ifdef CUTAWAY
// (EmpireKit.cut_mat: a hull with a doorway into its insides - a box of its own space not drawn)
instance uniform vec3 cut_lo = vec3(0.0);
instance uniform vec3 cut_hi = vec3(0.0);
#endif
varying vec3 v_nrm;
varying vec4 v_col;

uniform float sway = 0.0;           // m: the banners' sway at their foot (UV.y 0 at the top: hung still there)

void vertex() {
	v_obj = VERTEX;
	v_nrm = NORMAL;
	v_col = COLOR;
	if (sway > 0.0 && abs((zone_override >= 0.0 ? zone_override : COLOR.r * 16.0) - 7.0) < 0.5) {
		float w = UV.y * UV.y;
		VERTEX += NORMAL * sin(TIME * 0.9 + VERTEX.x * 0.031 + VERTEX.z * 0.027 + UV.x * 1.3) * w * sway;
	}
}

float n3(vec3 p) {
	return texture(noise_tex, p).r;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Seams on a grid across the face's main plane: x 0 on a seam .. 1, y the block's own number.
vec2 seams(vec3 p, vec3 n) {
	vec3 a = abs(n);
	vec2 q = a.x > a.y && a.x > a.z ? p.zy : (a.y > a.z ? p.xz : p.xy);
	q /= panel;
	q.y *= 1.6;
	q.x += 0.5 * step(0.5, fract(floor(q.y) * 0.5)) * blocks;   // (masonry: every other course half a block along)
	vec2 f = abs(fract(q + 0.5) - 0.5) * panel;
	float d = min(f.x, f.y / 1.6);
	float far = smoothstep(0.01, 0.05, fwidth(q.x * panel));   // (too small to see: no seam - nor its shimmer)
	float w = mix(1.0, 2.2, blocks);
	return vec2(mix(smoothstep(0.012 * w, 0.035 * w, d), 1.0, far), hash2(floor(q + 0.5)));
}

float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return 1.0 - smoothstep(w, w * 1.15, length(pa - ba * h));
}

float ring(vec2 p, float r, float w) {
	return 1.0 - smoothstep(w, w * 1.2, abs(length(p) - r));
}

// The triskelion: three spirals round the middle.
float triskelion(vec2 p) {
	float r0 = length(p);
	float ink = 0.0;
	float best = 9.0;
	vec2 bq = vec2(0.0);
	for (int k = 0; k < 3; k++) {
		float a = 1.5708 + float(k) * 2.0944;
		vec2 c = vec2(cos(a), sin(a)) * 0.33;
		vec2 q = p - c;
		float d = length(q);
		if (d < best) { best = d; bq = q; }
	}
	if (best < 0.3) {
		float a = atan(bq.y, bq.x);
		float t = (best / 0.075 - a / 6.2832);
		float line = abs(fract(t) - 0.5);
		ink = max(ink, smoothstep(0.24, 0.3, line) * smoothstep(0.3, 0.26, best));
	}
	float a0 = atan(p.y, p.x);
	float arm = abs(fract(a0 / 2.0944 + r0 * 0.9) - 0.5);
	ink = max(ink, smoothstep(0.43, 0.47, arm) * smoothstep(0.2, 0.05, r0));
	return ink;
}

// A wreath round the rim: leaves in pairs (Athens', Sparta's laurel).
float laurel(vec2 p, float r, float from, float to) {
	float a = atan(p.y, p.x);
	float t = (a + 3.14159) / 6.2832;
	if (t < from || t > to) return 0.0;
	float k = fract(t * 26.0) - 0.5;
	float d = abs(length(p) - r) - 0.05 * (1.0 - abs(k) * 2.0);
	return 1.0 - smoothstep(0.0, 0.012, d);
}

// The emblem in the unit disc (p: -1..1, y up): 1 where its ink is.
float device(vec2 p) {
	float ink = 0.0;
	if (emblem == 0) {
		ink = triskelion(p);
	} else if (emblem == 1) {
		// (the owl: a body, a round head, great eyes, ear tufts, a beak; a laurel round it)
		vec2 b = (p - vec2(0.0, -0.2)) / vec2(0.27, 0.36);
		ink = step(dot(b, b), 1.0);
		ink = max(ink, step(length(p - vec2(0.0, 0.22)), 0.27));
		ink = max(ink, seg(p, vec2(-0.2, 0.36), vec2(-0.27, 0.56), 0.05));
		ink = max(ink, seg(p, vec2(0.2, 0.36), vec2(0.27, 0.56), 0.05));
		vec2 e = vec2(abs(p.x) - 0.115, p.y - 0.25);
		ink *= 1.0 - step(length(e), 0.095);
		ink = max(ink, step(length(e), 0.045));
		ink *= 1.0 - seg(p, vec2(0.0, 0.2), vec2(0.0, 0.08), 0.03);
		ink *= 1.0 - seg(vec2(abs(p.x), p.y), vec2(0.1, -0.1), vec2(0.2, -0.42), 0.012);   // (the wings' edges)
		ink = max(ink, laurel(p, 0.74, 0.05, 0.95));
	} else if (emblem == 2) {
		// (the lambda, a laurel under it)
		vec2 q = vec2(abs(p.x), p.y);
		ink = seg(q, vec2(0.0, 0.5), vec2(0.36, -0.36), 0.085);
		ink = max(ink, laurel(p, 0.72, 0.55, 0.95));
	} else if (emblem == 3) {
		// (the rosette: eight petals round a boss)
		float r = length(p);
		float a = atan(p.y, p.x);
		float petal = 0.28 + 0.4 * pow(abs(cos(a * 4.0)), 0.6);
		ink = step(r, petal) * step(0.16, r);
		ink *= 1.0 - (1.0 - smoothstep(0.0, 0.05, abs(sin(a * 4.0)))) * step(0.2, r);
		ink = max(ink, step(r, 0.11));
		ink = max(ink, ring(p, 0.8, 0.03));
	} else if (emblem == 4) {
		// (the lyre: two arms curving up from a sound box, a yoke, its strings)
		vec2 q = vec2(abs(p.x), p.y);
		float arm = ring(q - vec2(0.12, 0.0), 0.3, 0.045) * step(-0.15, p.y) * step(0.12, q.x);
		ink = arm;
		ink = max(ink, seg(p, vec2(-0.42, 0.34), vec2(0.42, 0.34), 0.04));
		vec2 box = (p - vec2(0.0, -0.3)) / vec2(0.3, 0.2);
		ink = max(ink, step(dot(box, box), 1.0));
		float strings = step(abs(fract(p.x * 9.0 + 0.5) - 0.5), 0.12) * step(abs(p.x), 0.2) * step(-0.2, p.y) * step(p.y, 0.34);
		ink = max(ink, strings);
		ink = max(ink, seg(p, vec2(0.0, -0.5), vec2(0.0, -0.62), 0.05));
	} else if (emblem == 5) {
		// (the spiral, wound out from the middle)
		float r = length(p);
		float a = atan(p.y, p.x);
		float t = r / 0.2 - a / 6.2832;
		ink = (1.0 - smoothstep(0.16, 0.22, abs(fract(t) - 0.5))) * step(r, 0.78);
		ink = max(ink, step(r, 0.07));
	} else if (emblem == 6) {
		// (the skull over crossed bones)
		vec2 q = vec2(abs(p.x), p.y);
		float bones = max(seg(p, vec2(-0.55, -0.5), vec2(0.55, 0.3), 0.06), seg(p, vec2(0.55, -0.5), vec2(-0.55, 0.3), 0.06));
		bones = max(bones, step(length(q - vec2(0.57, 0.33)), 0.09));
		bones = max(bones, step(length(q - vec2(0.57, -0.53)), 0.09));
		vec2 c = (p - vec2(0.0, 0.14)) / vec2(0.36, 0.33);
		float skull = step(dot(c, c), 1.0);
		skull = max(skull, step(abs(p.x), 0.2) * step(-0.36, p.y) * step(p.y, 0.0));
		skull *= 1.0 - step(length((q - vec2(0.15, 0.12)) / vec2(0.1, 0.11)), 1.0);
		skull *= 1.0 - seg(p, vec2(0.0, -0.02), vec2(0.0, -0.1), 0.035);
		skull *= 1.0 - step(abs(fract(p.x * 7.0) - 0.5), 0.1) * step(p.y, -0.22) * step(-0.36, p.y);
		ink = max(bones * (1.0 - step(dot(c * 0.9, c * 0.9), 1.0)), skull);
	} else {
		// (a plain star of eight points)
		float r = length(p);
		float a = atan(p.y, p.x);
		ink = step(r, 0.3 + 0.38 * pow(abs(cos(a * 4.0)), 3.0));
		ink = max(ink, ring(p, 0.8, 0.03));
	}
	return clamp(ink, 0.0, 1.0);
}

// The bull's head (the Minoans' banner).
float bull(vec2 p) {
	vec2 f = p - vec2(0.0, 0.02);
	float w = mix(0.17, 0.1, clamp((f.y + 0.1) / 0.3, 0.0, 1.0));
	float face = step(abs(f.x), w) * step(-0.12, f.y) * step(f.y, 0.2);
	face = max(face, step(length((f - vec2(0.0, 0.2)) / vec2(0.1, 0.06)), 1.0));
	vec2 h = p - vec2(0.0, -0.06);
	float rr = length(h);
	float horns = step(0.2, rr) * step(rr, 0.26) * step(h.y, -0.02) * step(0.12, abs(h.x));
	float ears = step(length((abs(p - vec2(0.0, -0.07)) - vec2(0.2, 0.0)) / vec2(0.07, 0.035)), 1.0);
	float eyes = step(length(abs(p - vec2(0.0, 0.0)) - vec2(0.075, 0.0)), 0.025);
	float nose = step(length(abs(p - vec2(0.0, 0.23)) - vec2(0.04, 0.0)), 0.018);
	return max(max(face, horns), ears) * (1.0 - max(eyes, nose));
}

// A banner (uv: 0..1 across, 0 at the top): the emblem on it, a band at its foot, an edge.
float banner(vec2 uv) {
	float ink;
	if (emblem == 0) {
		ink = bull((uv - vec2(0.5, 0.42)) * vec2(1.0, 1.45));
	} else {
		ink = device((uv - vec2(0.5, 0.4)) * vec2(2.6, -3.9));
	}
	float wave = step(0.8, uv.y) * step(uv.y, 0.92) * step(abs(uv.y - 0.86 - 0.035 * sin(uv.x * 25.0)), 0.025);
	float edge = step(uv.x, 0.04) + step(0.96, uv.x) + step(0.97, uv.y) + step(uv.y, 0.02);
	return clamp(ink + wave + edge, 0.0, 1.0);
}

// The frieze (x: along, in repeats; y: 0 at its foot .. 1): 1 where its ink is.
float frieze_at(float x, float y) {
	float ink = 0.0;
	if (frieze == 0) {
		// (the running wave: crests curling over, a band under them)
		float crest = 0.42 + 0.2 * sin(6.2832 * (x - 0.25));
		ink = step(y, crest) * step(0.14, y);
		vec2 c = vec2(fract(x + 0.12), y) - vec2(0.5, 0.56);
		float rr = length(c * vec2(1.0, 1.3));
		ink = clamp(ink + step(0.1, rr) * step(rr, 0.2) * step(c.x + c.y * 0.3, 0.12), 0.0, 1.0);
		ink = max(ink, step(y, 0.08));
	} else if (frieze == 1) {
		// (the meander: a key turning in on itself, lines above and below)
		vec2 q = vec2(x, y);
		ink = step(y, 0.1) + step(0.9, y);
		ink += step(0.08, q.x) * step(q.x, 0.2) * step(0.22, y) * step(y, 0.78);
		ink += step(0.08, q.x) * step(q.x, 0.8) * step(0.66, y) * step(y, 0.78);
		ink += step(0.68, q.x) * step(q.x, 0.8) * step(0.36, y) * step(y, 0.78);
		ink += step(0.38, q.x) * step(q.x, 0.8) * step(0.36, y) * step(y, 0.48);
		ink += step(0.38, q.x) * step(q.x, 0.5) * step(0.22, y) * step(y, 0.48);
		ink += step(0.22, y) * step(y, 0.34) * (step(0.38, q.x) + step(q.x, 0.2));   // (on into the next key)
	} else if (frieze == 2) {
		// (lambdas in a row between two lines)
		vec2 q = vec2(abs(x - 0.5), y);
		ink = seg(q, vec2(0.0, 0.76), vec2(0.26, 0.24), 0.06);
		ink = max(ink, step(y, 0.1) + step(0.9, y));
	} else if (frieze == 3) {
		// (rosettes in a row)
		vec2 q = vec2(x - 0.5, y - 0.5) * 2.0;
		float r = length(q);
		float a = atan(q.y, q.x);
		ink = step(r, 0.34 + 0.34 * pow(abs(cos(a * 4.0)), 0.7)) * step(0.2, r);
		ink = max(ink, step(r, 0.13));
		ink = max(ink, step(y, 0.08) + step(0.92, y));
	} else if (frieze == 4) {
		// (spirals in a row, joined)
		vec2 q = vec2(x - 0.5, y - 0.5) * 2.0;
		float r = length(q);
		float a = atan(q.y, q.x);
		ink = (1.0 - smoothstep(0.14, 0.2, abs(fract(r / 0.34 - a / 6.2832) - 0.5))) * step(r, 0.78);
		ink = max(ink, step(abs(y - 0.5), 0.05) * step(0.78, r));
	} else {
		// (teeth: a jagged row)
		ink = step(y, 0.15 + 0.7 * abs(fract(x) - 0.5) * 2.0);
	}
	return clamp(ink, 0.0, 1.0);
}

void fragment() {
#ifdef CUTAWAY
	if (all(greaterThan(v_obj, cut_lo)) && all(lessThan(v_obj, cut_hi))) {
		discard;
	}
#endif
	int zone = int(round((zone_override >= 0.0 ? zone_override : v_col.r * 16.0)));
	vec3 p = v_obj;
	float big = n3(p * 0.045);
	float mid = n3(p * 0.21 + vec3(7.1));
	float fine = n3(p * 1.3 + vec3(2.3));
	float grain = n3(p * 5.0);
	vec3 col = cream;
	float rough = 0.55;
	float met = 0.0;
	vec3 emit = vec3(0.0);
	bool painted = false;
	if (zone == 0 || zone == 1 || zone == 14) {
		painted = true;
		col = zone == 0 ? cream : (zone == 1 ? red : accent2);
		col *= 0.88 + 0.24 * mid;
		rough = 0.5 + 0.2 * fine;
	} else if (zone == 2) {
		col = iron * (0.75 + 0.5 * mid);
		rough = 0.35 + 0.35 * fine;
		met = 0.75;
	} else if (zone == 3) {
		col = steel * (0.85 + 0.25 * fine);
		rough = 0.22 + 0.2 * mid;
		met = 0.95;
	} else if (zone == 13) {
		col = gold * (0.8 + 0.3 * fine);
		rough = 0.24 + 0.2 * mid;
		met = 0.95;
	} else if (zone == 4) {
		col = amber;
		emit = amber * 3.2 * glow;
		rough = 0.3;
	} else if (zone == 5) {
		vec2 q = UV * 2.0 - 1.0;
		float rr = length(q);
		float rings = smoothstep(0.04, 0.0, abs(fract(rr * 4.0) - 0.5) - 0.44);
		float grid = smoothstep(0.03, 0.0, min(abs(fract(UV.x * 8.0) - 0.5), abs(fract(UV.y * 5.0) - 0.5)) - 0.46);
		float sweep = pow(max(0.0, cos(atan(q.y, q.x) - TIME * 1.3)), 24.0) * step(rr, 1.0);
		col = vec3(0.02, 0.04, 0.06);
		emit = screen * (0.25 + 0.9 * max(rings * step(rr, 1.0), grid * 0.5) + sweep) * glow;
		rough = 0.08;
		met = 0.0;
	} else if (zone == 6) {
		vec2 q = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
		float r0 = length(q);
		float ink = device(q / 0.82) * step(r0, 0.8);
		float rim = smoothstep(0.84, 0.86, r0) * (1.0 - smoothstep(0.93, 0.95, r0));
		painted = true;
		col = mix(emblem_ground, emblem_ink, max(ink, rim)) * (0.88 + 0.24 * mid);
		rough = 0.5;
	} else if (zone == 7) {
		float ink = banner(UV);
		col = mix(red * 0.9, mix(cream, gold, 0.35), ink);
		col *= 0.8 + 0.3 * grain;   // (the weave)
		rough = 0.85;
	} else if (zone == 8) {
		col = vec3(0.86, 0.8, 0.7) * (0.8 + 0.3 * fine) * (0.92 + 0.08 * grain);
		rough = 0.45 + 0.2 * fine;
	} else if (zone == 9) {
		col = red * 1.05 * (0.85 + 0.2 * grain);
		rough = 0.8;
		if (v_col.g > 0.5) {
			// (a border: two gold lines, a row of squares between them)
			vec2 e = min(UV, 1.0 - UV) * vec2(1.0, 4.0);
			float d = min(e.x, e.y);
			float along = e.x < e.y ? UV.y * 4.0 : UV.x;
			float lines = step(0.03, d) * step(d, 0.045) + step(0.13, d) * step(d, 0.145);
			float sq = step(0.065, d) * step(d, 0.11) * step(0.5, fract(along * 7.0));
			col = mix(col, vec3(0.8, 0.62, 0.34), clamp(lines + sq, 0.0, 1.0));
		}
	} else if (zone == 10) {
		col = vec3(0.12, 0.3, 0.08) * (0.7 + 0.6 * fine);
		rough = 0.6;
	} else if (zone == 12) {
		float reps = max(1.0, round(v_col.g * 40.0));
		float ink = frieze_at(fract(UV.x * reps), 1.0 - UV.y);
		painted = true;
		col = mix(frieze_ground, frieze_ink, ink) * (0.88 + 0.24 * mid);
		rough = 0.5;
	} else if (zone == 15) {
		// (wood: the grain's rings along it, warped; a satin varnish)
		float w = n3(p * vec3(0.08, 0.6, 0.6));
		float ring = fract((p.z + p.y * 0.6) * 9.0 + w * 2.2);
		float fib = n3(p * vec3(0.4, 14.0, 14.0));
		col = mix(vec3(0.26, 0.13, 0.06), vec3(0.40, 0.23, 0.11), smoothstep(0.3, 0.7, ring) * 0.6 + fib * 0.4) * (0.92 + 0.16 * mid);
		rough = 0.32 + 0.15 * grain;
	} else if (zone == 11) {
		float s = step(0.5, fract((p.x + p.z) * 2.5));
		col = mix(vec3(0.05), vec3(0.9, 0.7, 0.1), s);
		rough = 0.6;
	}
	if (painted) {
		// (seams, grime gathering low and in them, chips to bare metal, streaks; stone: blocks, veins)
		vec2 sm = seams(p, v_nrm);
		float s = sm.x;
		col *= mix(mix(0.45, 0.3, blocks), 1.0, s);
		col *= 1.0 + (sm.y - 0.5) * 0.3 * blocks;
		if (marble > 0.0) {
			float vein = n3(p * 0.11 + vec3(n3(p * 0.3) * 0.5));
			col *= 1.0 - marble * 0.3 * (1.0 - smoothstep(0.0, 0.035, abs(vein - 0.5)));
			rough = mix(rough, 0.22, marble * 0.6);
		}
		float grime = smoothstep(0.35, 0.8, big * 0.6 + mid * 0.4) * 0.35 * wear;
		col *= 1.0 - grime;
		float streak = smoothstep(0.55, 0.75, n3(p * vec3(1.6, 0.08, 1.6))) * 0.25 * wear;
		col *= 1.0 - streak;
		float chip_n = n3(p * 0.4 + vec3(4.7)) * 0.7 + n3(p * 1.1) * 0.3;
		float chip = smoothstep(0.72, 0.75, chip_n + (1.0 - s) * 0.06) * wear * (1.0 - marble) * (1.0 - blocks);
		col = mix(col, steel * 0.7 * (0.75 + 0.4 * grain), chip);
		met = mix(met, 0.35, chip);
		rough = mix(rough, 0.4, chip);
	}
	if (zone == 6 || zone == 7 || zone == 12) {
		emit += col * flood;
	}
	if (!FRONT_FACING) {
		// (the hull's inside: bare dark metal)
		col = iron * 0.6;
		met = 0.3;
		rough = 0.7;
		emit = vec3(0.0);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = met * (1.0 - inside * 0.7);
	SPECULAR = 0.5;
	EMISSION = emit;
}
