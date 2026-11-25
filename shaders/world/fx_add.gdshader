// Fx's light particles (CPUParticles3D - data/effects.json): added over the scene,
// unlit. One shader for every bright particle, its look by `kind`:
//   0 glow  - a soft round light (a flash, a muzzle's, a hot core)
//   1 fire  - a billow of flame: ragged by noise, burning away as it ages
//   2 spark - a streak along its flight (the emitter aligns its Y to the velocity),
//             turned to face the camera
//   3 ring  - a thin bright ring (a shockwave: flat, billboard off)
// The colour (and how bright: values over 1) is the particle's COLOR - the
// emitter's colour ramp times its emissive strength. INSTANCE_CUSTOM: x the
// particle's angle, y its age (0-1).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled, shadows_disabled;

uniform int kind = 0;
uniform bool billboard = true;

varying float v_seed;
varying float v_age;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_seed = fract(float(INSTANCE_ID) * 0.6180339 + 0.13);
	v_age = INSTANCE_CUSTOM.y;
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	if (kind == 2) {
		// The streak: its length along the flight, its face to the camera.
		vec3 y = MODEL_MATRIX[1].xyz / max(sc.y, 0.0001);
		vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
		vec3 x = cross(y, to_cam);
		x = length(x) > 0.0001 ? normalize(x) : normalize(INV_VIEW_MATRIX[0].xyz);
		vec3 z = cross(x, y);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(x * sc.x, 0.0), vec4(y * sc.y, 0.0), vec4(z * sc.z, 0.0), MODEL_MATRIX[3]);
	} else if (billboard) {
		float a = INSTANCE_CUSTOM.x;
		mat4 m = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
		m = m * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * m * mat4(vec4(sc.x, 0.0, 0.0, 0.0), vec4(0.0, sc.y, 0.0, 0.0), vec4(0.0, 0.0, sc.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float g;
	if (kind == 1) {
		// Flame: two octaves of noise drifting outward; the thin parts burn off with age.
		vec2 q = c * 1.6 + v_seed * 17.0;
		float n = vnoise(q * 1.7 + vec2(0.0, -v_age * 2.0)) * 0.62 + vnoise(q * 3.9 - vec2(v_age * 1.3, 0.0)) * 0.38;
		float body = smoothstep(1.0, 0.25, r + (n - 0.5) * 0.9);
		float burn = smoothstep(v_age * 0.85 - 0.1, v_age * 0.85 + 0.25, n);
		g = body * burn * (0.55 + n * 0.9) * smoothstep(1.0, 0.6, r);   // (nothing at the quad's edge)
		g += exp(-r * r * 9.0) * 0.35 * (1.0 - v_age);
	} else if (kind == 2) {
		float across = abs(UV.x * 2.0 - 1.0);
		g = smoothstep(1.0, 0.0, across) * smoothstep(0.0, 0.35, UV.y) * smoothstep(1.0, 0.7, UV.y);
		g = g * g * 1.6;
	} else if (kind == 3) {
		float d = abs(r - 0.82);
		g = exp(-d * d * 260.0) + exp(-d * 18.0) * 0.18;
		g *= smoothstep(1.0, 0.94, r);
	} else {
		g = exp(-r * r * 6.0) * 0.65 + exp(-r * 16.0) * 0.55;
		g *= smoothstep(1.0, 0.8, r);
	}
	ALBEDO = COLOR.rgb * g * COLOR.a;
}
