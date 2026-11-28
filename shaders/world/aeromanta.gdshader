// The aeromanta (CosmosAeromanta): a sky manta's skin and its motion.
// Moving: waves travelling from the body out to the wing tips (`phase` the
// beat, `wave` how deep: a glide ~0.15, swimming hard 1), the normals bent with
// them; the whip tail (UV2.x: how far along it) rippling and trailing a turn
// (`bend`). Its skin: the back dark in c1, mottled, pale shoulder marks in c2;
// the belly pale (c2) with a few dark spots near the middle and darker margins;
// five gill slits each side under the head, the wide mouth dark; the eyes dark
// glass (COLOR.g); the fins (COLOR.b) as the back. A flash when hit.
shader_type spatial;
render_mode cull_back;

uniform vec4 c1 : source_color = vec4(0.2, 0.35, 0.6, 1.0);
uniform vec4 c2 : source_color = vec4(0.85, 0.9, 1.0, 1.0);
uniform float span = 1.45;
uniform float phase = 0.0;
uniform float wave = 0.3;
uniform float bend = 0.0;
uniform float flash = 0.0;
uniform sampler3D noise_tex : filter_linear, repeat_enable;

varying vec3 v_obj;
varying vec3 v_on;

float wave_y(float a, float z) {
	return wave * 0.3 * pow(smoothstep(0.07, 1.0, a), 1.3) * sin(phase - a * 3.4 - (z + 0.5) * 1.3);
}

void vertex() {
	v_obj = VERTEX;
	v_on = NORMAL;
	float t = UV2.x;
	if (t <= 0.0) {
		float a = clamp(abs(VERTEX.x) / span, 0.0, 1.0);
		float w = wave_y(a, VERTEX.z);
		float da = 0.01;
		float gx = (wave_y(min(a + da, 1.0), VERTEX.z) - w) / (da * span) * sign(VERTEX.x);
		float gz = (wave_y(a, VERTEX.z + 0.01) - w) / 0.01;
		VERTEX.y += w;
		NORMAL = normalize(vec3(NORMAL.x - gx * NORMAL.y, NORMAL.y, NORMAL.z - gz * NORMAL.y));
	} else {
		float amp = 0.3 + wave;
		VERTEX.x += sin(phase * 1.3 - t * 7.0) * 0.1 * t * amp + bend * t * t * 0.7;
		VERTEX.y += sin(phase * 0.9 - t * 5.0) * 0.05 * t * amp - t * t * 0.05;
	}
}

void fragment() {
	float n = texture(noise_tex, v_obj * 1.5).r;
	float n2 = texture(noise_tex, v_obj * 6.0 + 3.1).r;
	float ax = abs(v_obj.x);
	float a = clamp(ax / span, 0.0, 1.0);
	float z = v_obj.z;
	float top = smoothstep(-0.25, 0.25, v_on.y);
	// The back: dark, mottled, the pale shoulder marks (a chevron behind the head).
	vec3 back = c1.rgb * 0.25 * (0.75 + 0.45 * n2) * (0.85 + 0.3 * n);
	float zc = -0.32 + ax * 0.55 + (n - 0.5) * 0.08;   // (a chevron: its arms swept back along the wings)
	float chev = 1.0 - smoothstep(0.03, 0.16 * (1.0 - ax), abs(z - zc));
	chev *= smoothstep(0.08, 0.2, ax) * (1.0 - smoothstep(0.3, 0.6 + 0.15 * n, ax)) * smoothstep(0.2, 0.5, n2 + 0.2);
	back = mix(back, c2.rgb * 0.7 * (0.85 + 0.2 * n2), chev * 0.55);
	back *= mix(1.0, 0.7, smoothstep(0.75, 1.0, a));   // (the tips darker)
	// The belly: pale, darker toward the margins, a few spots near the middle.
	vec3 belly = c2.rgb * (0.88 + 0.12 * n);
	belly = mix(belly, c1.rgb * 0.45, smoothstep(0.55, 1.0, a) * 0.65);
	float spots = smoothstep(0.66, 0.7, texture(noise_tex, v_obj * 4.0 + 7.3).r) * (1.0 - smoothstep(0.12, 0.3, ax)) * step(-0.3, z);
	belly = mix(belly, c1.rgb * 0.25, spots * 0.8);
	// Its gill slits (five each side under the head) and the mouth.
	float below = 1.0 - top;
	float slit_band = smoothstep(0.08, 0.1, ax) * (1.0 - smoothstep(0.19, 0.21, ax)) * step(-0.39, z) * step(z, -0.2);
	float slit = (1.0 - smoothstep(0.003, 0.006, abs(fract((z + 0.39) / 0.038) - 0.5) * 0.038)) * slit_band;
	float mouth = (1.0 - smoothstep(0.1, 0.12, ax)) * smoothstep(-0.49, -0.53, z) * smoothstep(0.4, -0.2, v_on.y);
	belly = mix(belly, vec3(0.04, 0.04, 0.05), max(slit * below, mouth));
	vec3 col = mix(belly, back, top);
	if (UV2.x > 0.0) {
		col = c1.rgb * 0.4 * (0.8 + 0.3 * n2);   // (the tail: dark all round)
	}
	float rough = 0.48 + 0.12 * n2;
	// The eyes: dark glass.
	if (COLOR.g > 0.5) {
		col = vec3(0.02, 0.02, 0.025);
		rough = 0.08;
	}
	// The fins: the back's colour, a paler inside to the cephalic fins.
	if (COLOR.b > 0.5) {
		col = mix(c1.rgb * 0.45 * (0.8 + 0.3 * n2), c2.rgb * 0.7, smoothstep(0.3, 0.9, -v_on.y) * 0.7);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.35;
	// (a wet, living sheen at a slant)
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO += c2.rgb * pow(1.0 - ndv, 4.0) * 0.08;
	EMISSION = vec3(1.0, 0.25, 0.15) * flash;
}
