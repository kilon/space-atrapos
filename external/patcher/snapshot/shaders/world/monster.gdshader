shader_type spatial;
// A space monster (CosmosMonster): one mesh, moving here - every vertex says
// how it sways (CUSTOM0: its phase along its limb, how far, its glow, which
// way: 0 still, 1 side to side (swimming), 2 up and down (fins), 3 writhing
// (tentacles, necks), 4 turning round its axis (a vortex), 5 fore and aft
// (striding legs)). COLOR: the albedo, its alpha 1 - metallic (gold, bronze).
// Its skin mottled and scaled by a little noise; the glow gathers before an
// attack (charge); a flash when hit.
render_mode cull_back;

uniform float speed = 1.0;
uniform float wave = 1.0;
uniform float charge = 0.0;
uniform float flash = 0.0;
uniform vec4 glow_color : source_color = vec4(0.45, 1.0, 0.55, 1.0);

varying vec4 v_c;
varying vec3 v_obj;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	v_c = CUSTOM0;
	v_obj = VERTEX;
	float ph = CUSTOM0.x;
	float amp = CUSTOM0.y * wave;
	int g = int(CUSTOM0.w + 0.5);
	float t = TIME * speed;
	float s = sin(t * 1.3 - ph);
	if (g == 1) {
		VERTEX.x += s * amp;
	} else if (g == 2) {
		VERTEX.y += s * amp;
	} else if (g == 3) {
		VERTEX.x += s * amp;
		VERTEX.y += cos(t * 1.1 - ph * 1.3) * amp * 0.7;
	} else if (g == 4) {
		float a = t * 0.8;
		VERTEX.xy = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * VERTEX.xy;
	} else if (g == 5) {
		VERTEX.z += s * amp;
		VERTEX.y += max(cos(t * 1.3 - ph), 0.0) * amp * 0.3;
	}
}

void fragment() {
	float n = vnoise(v_obj * 0.08) * 0.5 + vnoise(v_obj * 0.4) * 0.3 + vnoise(v_obj * 2.0) * 0.2;
	float metal = 1.0 - COLOR.a;
	vec3 c = COLOR.rgb * (0.75 + 0.5 * n);
	ALBEDO = c;
	METALLIC = metal;
	ROUGHNESS = mix(0.6 - 0.2 * n, 0.3, metal);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = glow_color.rgb * (v_c.z * (1.0 + charge * 4.0) + rim * 0.15) + vec3(1.0, 0.3, 0.2) * flash;
}
