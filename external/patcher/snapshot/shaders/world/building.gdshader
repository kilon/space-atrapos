shader_type spatial;
// The towns' buildings and the dungeons (CosmosTown, CosmosDungeon): one mesh
// a town, each piece's part of the palette in its vertices (COLOR.r = the
// slot: walls, stone, columns, frescos, trim...; COLOR.g = a little variation
// a piece; COLOR.b = its base's height, mod 8 m) - the colours themselves are
// these parameters: a town recoloured by setting them. Its surfaces made here,
// procedurally, on the face's own plane: plaster mottled by the world's noise, cut stone
// in courses of ashlar blocks (their joints darker, each block its own tone),
// the frescoes' running spirals between red borders, wood's grain; grime near
// the ground.
render_mode cull_back;

uniform vec4 slot_color[14];
uniform vec4 slot_look[14];   // x roughness, y metallic (13: a town lamp's metal - TownLamps)
uniform float ashlar = 1.0;
uniform float cyclopean = 0.0;   // (Mycenae's: the cut stone in great many-sided blocks)
uniform int band_style = 0;      // the fresco band: 0 running spirals, 1 the meander, 2 lambdas, 3 rosettes, 4 egg and dart
uniform vec3 band_ink : source_color = vec3(0.93, 0.88, 0.74);
uniform vec4 paint_color[9];     // (built pieces - BuildKit: COLOR.a = 1 - paint / 16, a paint over the plaster, wood, tiles)
uniform vec3 glow_color : source_color = vec3(1.0, 0.55, 0.18);   // (slot 12: a lamp's flame, a kiln's mouth)
instance uniform float lamp_lit = 1.0;   // (slot 14: a town lamp's flame - TownLamps: 0 by day (sunk into its bowl, out), 1 by night)
uniform sampler3D noise_tex : filter_linear, repeat_enable;   // (the world's 3D noise: the plaster's mottling, three lookups)   // 1: the stone slot in courses; 2: the walls too (a dungeon); 0: rough (a cave)

varying vec3 v_obj;
varying vec3 v_n;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	if (int(COLOR.r * 255.0 + 0.5) == 14) {
		// (a town lamp's flame: COLOR.g how far up it, COLOR.b its height - swaying, flickering
		// taller and shorter; by day sunk to its foot: its bowl's oil)
		float up = COLOR.g;
		float h = COLOR.b;
		float ph = VERTEX.x * 1.7 + VERTEX.z * 2.3;
		float sway = up * up * h * 0.16 * lamp_lit;
		VERTEX.x += sin(TIME * 5.3 + ph + up * 2.0) * sway;
		VERTEX.z += cos(TIME * 4.1 + ph * 1.3 + up * 1.6) * sway;
		VERTEX.y += up * h * (0.1 * sin(TIME * 9.0 + ph * 2.0) * lamp_lit - (1.0 - lamp_lit));
		NORMAL = normalize(mix(vec3(0.0, 1.0, 0.0), NORMAL, lamp_lit));
	}
	v_obj = VERTEX;
	v_n = NORMAL;
}

vec2 hash22(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// Many-sided blocks: x how far from a joint (0 on it), y the block's own number.
vec2 polygons(vec2 uv) {
	vec2 g = floor(uv);
	vec2 f = fract(uv);
	float d1 = 9.0, d2 = 9.0, id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 h = hash22(g + o);
			float d = length(o + 0.15 + 0.7 * h - f);
			if (d < d1) { d2 = d1; d1 = d; id = h.x; } else if (d < d2) { d2 = d; }
		}
	}
	return vec2(d2 - d1, id);
}

float bseg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return 1.0 - smoothstep(w, w * 1.2, length(pa - ba * h));
}

// The band's pattern (x: along, in repeats; y: 0 at its foot .. 1): 1 where its ink is.
float band_at(float x, float y) {
	float ink = 0.0;
	if (band_style == 1) {
		ink += step(0.08, x) * step(x, 0.2) * step(0.22, y) * step(y, 0.78);
		ink += step(0.08, x) * step(x, 0.8) * step(0.66, y) * step(y, 0.78);
		ink += step(0.68, x) * step(x, 0.8) * step(0.36, y) * step(y, 0.78);
		ink += step(0.38, x) * step(x, 0.8) * step(0.36, y) * step(y, 0.48);
		ink += step(0.38, x) * step(x, 0.5) * step(0.22, y) * step(y, 0.48);
		ink += step(0.22, y) * step(y, 0.34) * (step(0.38, x) + step(x, 0.2));
	} else if (band_style == 2) {
		ink = bseg(vec2(abs(x - 0.5), y), vec2(0.0, 0.76), vec2(0.26, 0.26), 0.06);
	} else if (band_style == 3) {
		vec2 q = vec2(x - 0.5, y - 0.5) * 2.0;
		float r = length(q);
		float a = atan(q.y, q.x);
		ink = step(r, 0.3 + 0.32 * pow(abs(cos(a * 4.0)), 0.7)) * step(0.18, r);
		ink = max(ink, step(r, 0.12));
	} else if (band_style == 4) {
		// (eggs between darts)
		vec2 e = vec2((x - 0.35) / 0.24, (y - 0.5) / 0.34);
		ink = step(dot(e, e), 1.0) * (1.0 - step(dot(e * 1.5, e * 1.5), 1.0));
		ink = max(ink, bseg(vec2(x, y), vec2(0.82, 0.8), vec2(0.82, 0.3), 0.035));
		ink = max(ink, bseg(vec2(abs(x - 0.82), y), vec2(0.0, 0.2), vec2(0.07, 0.34), 0.03));
	}
	return clamp(ink, 0.0, 1.0);
}

// The face's own 2D coordinates (m): across it and up it (or x, z on top).
vec2 face_uv(vec3 p, vec3 n) {
	if (abs(n.y) > 0.7) return p.xz;
	return abs(n.x) > abs(n.z) ? vec2(p.z, p.y) : vec2(p.x, p.y);
}

void fragment() {
	int raw = int(COLOR.r * 255.0 + 0.5);
	int i = clamp(raw, 0, 13);
	float n = texture(noise_tex, v_obj * 0.22).r * 0.55 + texture(noise_tex, v_obj * 1.05).r * 0.3 + texture(noise_tex, v_obj * 4.6).r * 0.15;
	vec3 c = slot_color[i].rgb * (0.86 + 0.24 * n) * (0.93 + 0.14 * COLOR.g);
	int code = int((1.0 - COLOR.a) * 64.0 + 0.5);   // (built pieces: paint + 9 x wear)
	int pi = code % 9;
	int wear = code / 9;
	if (pi > 0 && (i == 0 || i == 2 || i == 9 || i == 10 || i == 11)) {
		c = paint_color[pi].rgb * (0.86 + 0.24 * n) * (0.93 + 0.14 * COLOR.g);
	}
	float rough = slot_look[i].x + (n - 0.5) * 0.15;
	vec2 uv = face_uv(v_obj, v_n);
	if (cyclopean > 0.5 && (i == 0 || i == 1)) {
		// Cyclopean: great many-sided blocks fitted together, each its own tone, deep joints.
		vec2 pg = polygons(uv / 1.15);
		float joint = 1.0 - smoothstep(0.02, 0.07, pg.x);
		c *= (0.82 + 0.3 * pg.y) * (1.0 - 0.6 * joint);
		rough = mix(rough, 1.0, joint);
	} else if ((i == 1 && ashlar > 0.5) || (i == 0 && ashlar > 1.5)) {
		// Ashlar: courses 0.42 m high, blocks 0.95 m, every other course offset.
		float row = floor(uv.y / 0.42);
		float x = uv.x / 0.95 + 0.5 * mod(row, 2.0);
		vec2 f = vec2(fract(x), fract(uv.y / 0.42));
		float g = min(min(f.x, 1.0 - f.x) * 0.95, min(f.y, 1.0 - f.y) * 0.42);
		float joint = 1.0 - smoothstep(0.006, 0.022, g);
		c *= (0.9 + 0.2 * hash(vec3(floor(x), row, 3.0))) * (1.0 - 0.55 * joint);
		rough = mix(rough, 1.0, joint);
	} else if (i == 5) {
		// The fresco band: running spirals, 0.5 m, between red borders.
		float base = COLOR.b * 8.0;
		float v = fract((mod(v_obj.y, 8.0) - base) / 0.5);
		vec2 p = vec2(fract(uv.x / 0.5) - 0.5, v - 0.5) * 2.0;
		float r = length(p);
		float a = atan(p.y, p.x) / 6.2831853;
		float sp = fract(a + r * 1.6);
		float line = (1.0 - smoothstep(0.1, 0.17, abs(sp - 0.5))) * (1.0 - smoothstep(0.78, 0.86, r));
		if (band_style > 0) {
			line = band_at(fract(uv.x / 0.5), clamp((v - 0.12) / 0.76, 0.0, 1.0)) * step(0.12, v) * step(v, 0.88);
		}
		c = mix(c, band_ink, line * 0.85);
		float border = 1.0 - smoothstep(0.06, 0.09, min(v, 1.0 - v));
		c = mix(c, slot_color[3].rgb, border);
	} else if (i == 9) {
		// Wood: its grain, streaks along the (mostly level) beams.
		float gr = texture(noise_tex, vec3(uv.x * 0.17, uv.y * 5.5, (v_obj.x + v_obj.z) * 0.25)).r;
		c *= 0.82 + 0.3 * gr;
	}
	c *= mix(0.72, 1.0, smoothstep(0.0, 1.6, v_obj.y));   // (grime splashed up from the ground)
	if (wear > 0 && raw != 12 && raw != 14) {   // (worn: soot and grime, then cracks across it - more, wider, the worse it is)
		vec2 pg = polygons(face_uv(v_obj, v_n) / (0.55 - 0.1 * float(wear)) + vec2(float(i) * 3.1, 0.0));
		float crack = (1.0 - smoothstep(0.0, 0.012 + 0.012 * float(wear), pg.x)) * step(0.45 - 0.15 * float(wear), pg.y);
		float soot = texture(noise_tex, v_obj * 0.6).r;
		c *= 1.0 - 0.1 * float(wear) * (0.6 + soot);
		c = mix(c, vec3(0.02), crack * 0.85);
		rough = mix(rough, 1.0, 0.15 * float(wear));
	}
	if (raw == 12 || raw == 14) {   // (a flame: lit from within, flickering with the noise as it drifts; a town's by night)
		float fl = texture(noise_tex, v_obj * 2.0 + vec3(0.0, -TIME * 1.3, 0.0)).r;
		float lit = raw == 14 ? lamp_lit : 1.0;
		c = mix(vec3(0.035, 0.028, 0.02), vec3(0.02), lit);   // (out: dark oil)
		EMISSION = glow_color * (2.2 + 2.4 * fl) * lit;
		rough = mix(0.25, 1.0, lit);
	}
	ALBEDO = c;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = (raw == 12 || raw == 14) ? 0.0 : slot_look[i].y;
	SPECULAR = 0.25;   // (plaster and stone: little of the sky mirrored - shaded sides not blue)
}
