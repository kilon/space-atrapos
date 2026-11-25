shader_type spatial;
// The 3D maps' worlds and suns: a sphere in its own colours (from its look -
// PlanetGen's), lit from the star (sun_pos) with a soft terminator, an
// atmosphere's rim on the day side, continents or a gas giant's bands from a
// little value noise. emit = 1: a star (its own light, a hot limb).
render_mode unshaded, fog_disabled, shadows_disabled;

uniform vec3 sun_pos = vec3(0.0);
uniform vec4 c_low : source_color = vec4(0.1, 0.2, 0.4, 1.0);
uniform vec4 c_mid : source_color = vec4(0.4, 0.4, 0.3, 1.0);
uniform vec4 c_high : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform vec4 c_air : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform float sea = 0.45;        // the share under the sea (low colour), rocky worlds
uniform float bands = 0.0;       // 1: a gas giant's bands
uniform float seed = 0.0;
uniform float emit = 0.0;        // 1: a star
uniform float air = 0.6;         // the rim's strength

varying vec3 v_world;
varying vec3 v_local;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = normalize(VERTEX);
}

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_world);
	vec3 p = v_local * 2.2 + vec3(seed * 0.37, seed * 0.11, seed * 0.23);
	float f = fbm(p);
	if (emit > 0.5) {
		float limb = pow(max(dot(n, v), 0.0), 0.6);
		vec3 hot = mix(c_mid.rgb, c_high.rgb, f);
		ALBEDO = mix(c_low.rgb * 1.3, hot * 1.25, limb) + vec3(0.25) * pow(limb, 6.0);
	} else {
		vec3 base;
		if (bands > 0.5) {
			float b = sin(v_local.y * 13.0 + f * 4.0 + seed) * 0.5 + 0.5;
			float b2 = sin(v_local.y * 31.0 + f * 6.0) * 0.5 + 0.5;
			base = mix(mix(c_low.rgb, c_mid.rgb, b), c_high.rgb, b2 * 0.35);
		} else {
			float h = f + 0.12 * fbm(p * 4.0);
			float land = smoothstep(sea, sea + 0.04, h);
			base = mix(c_low.rgb, mix(c_mid.rgb, c_high.rgb, smoothstep(sea + 0.1, sea + 0.32, h)), land);
		}
		vec3 l = normalize(sun_pos - v_world);
		float nl = dot(n, l);
		float day = smoothstep(-0.12, 0.45, nl);
		float rim = pow(1.0 - max(dot(n, v), 0.0), 3.0);
		vec3 col = base * (0.16 + 1.1 * max(nl, 0.0) * day + 0.12 * day);
		col += c_air.rgb * rim * air * smoothstep(-0.25, 0.3, nl);
		ALBEDO = col;
	}
}
