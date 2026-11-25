// The sea's animals (CosmosUnderwater), moved in the vertex shader: a school
// of fish (one MultiMesh: each fish its slot in the school, INSTANCE_CUSTOM
// rgb, and its own rhythm, a - wandering round its slot, its body waving,
// its heading wavering), a ray (its wings beating in a wave out to their
// tips), an eel or sea serpent (a wave down its length), a bloom of
// jellyfish (their bells pulsing, tentacles trailing; they glow). Vertex
// colours; the script moves only each group's node.
shader_type spatial;
render_mode cull_disabled;

uniform int kind = 0;            // 0 fish school, 1 ray, 2 eel, 3 jellyfish
uniform float pace = 1.0;        // the swimming's tempo (fleeing: faster)
uniform float spread = 3.0;      // m: a school's size
uniform float size = 0.3;        // m: a fish's length (a school's)
uniform float glow = 0.0;
uniform vec3 fill = vec3(0.0);   // the water's own light, all round

varying float v_part;

vec3 yaw(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c);
}

void vertex() {
	v_part = UV.x;
	float t = TIME * pace;
	if (kind == 0) {
		vec4 cd = INSTANCE_CUSTOM;
		float ph = cd.a * 6.2831;
		float s = size * (0.8 + 0.4 * fract(cd.a * 13.7));
		vec3 v = VERTEX;
		// (unit fish: nose at -z 0.5, tail at +z 0.5 - the wave grows to the tail)
		float tail = clamp(v.z + 0.55, 0.0, 1.2);
		v.x += sin(v.z * 7.0 - t * 11.0 + ph) * 0.06 * tail * tail;
		float a = sin(TIME * 0.7 + ph * 3.0) * 0.28 + sin(TIME * 1.9 + ph) * 0.08;
		VERTEX = yaw(v * s, a);
		NORMAL = yaw(NORMAL, a);
		vec3 slot = (cd.rgb * 2.0 - 1.0) * spread * vec3(1.0, 0.45, 1.6);
		slot += vec3(sin(TIME * 0.31 + ph * 5.0), sin(TIME * 0.23 + ph * 3.0) * 0.5, sin(TIME * 0.27 + ph * 7.0)) * spread * 0.22;
		VERTEX += slot;
	} else if (kind == 1) {
		// (a ray: wings span x, -1..1; their beat a wave travelling out to the tips)
		float ax = abs(VERTEX.x);
		VERTEX.y += sin(t * 1.7 - ax * 1.6) * pow(ax, 1.4) * 0.26;
		VERTEX.x += sin(VERTEX.z * 4.0 - t * 3.0) * 0.04 * smoothstep(0.4, 1.6, VERTEX.z);   // (its tail)
	} else if (kind == 2) {
		// (an eel: length along z, head at -0.5)
		float k = VERTEX.z + 0.5;
		VERTEX.x += sin(VERTEX.z * 11.0 - t * 4.5) * 0.045 * (0.25 + k);
	} else {
		vec4 cd = INSTANCE_CUSTOM;
		float ph = cd.a * 6.2831;
		vec3 v = VERTEX;
		float pulse = sin(t * 1.9 + ph);
		if (UV.x < 0.5) {
			// (the bell: its rim squeezes in, then opens)
			float rim = smoothstep(0.35, 0.0, v.y + 0.05);
			v.xz *= 1.0 - 0.14 * pulse * (0.4 + rim);
			v.y += 0.03 * pulse;
		} else {
			float hang = max(-v.y, 0.0);
			v.x += sin(TIME * 1.3 + ph + hang * 2.2) * 0.12 * hang;
			v.z += cos(TIME * 1.1 + ph * 1.7 + hang * 1.9) * 0.1 * hang;
			v.y += 0.05 * sin(t * 1.9 + ph - hang * 1.5) * hang;
		}
		float s = size * (0.75 + 0.5 * fract(cd.a * 7.3));
		VERTEX = v * s + (cd.rgb * 2.0 - 1.0) * spread + vec3(0.0, sin(TIME * 0.35 + ph) * 0.6, 0.0);
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	if (kind == 3) {
		float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		ALBEDO = COLOR.rgb * 0.35;
		EMISSION = COLOR.rgb * glow * (0.35 + 1.3 * rim * rim) * (v_part > 0.5 ? 0.7 : 1.0);
		ROUGHNESS = 0.2;
		SPECULAR = 0.8;
	} else {
		ROUGHNESS = kind == 0 ? 0.32 : 0.5;
		METALLIC = kind == 0 ? 0.25 * v_part : 0.0;   // (a fish's silver flanks)
		SPECULAR = 0.6;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;   // (fins, tentacles: both sides)
	}
	EMISSION += ALBEDO * fill;
}
