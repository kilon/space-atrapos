// Fx's smoke and dust particles (CPUParticles3D - data/effects.json): soft ragged
// billows blended over the scene, lit by the scene's lights (and through from
// behind), facing the camera. COLOR: the emitter's colour ramp (its alpha the
// fade) times the effect's tint (a landing's dust: the ground's colour).
// INSTANCE_CUSTOM: x the particle's angle, y its age (0-1).
shader_type spatial;
render_mode cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

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
	v_seed = fract(float(INSTANCE_ID) * 0.6180339 + 0.37);
	v_age = INSTANCE_CUSTOM.y;
	if (billboard) {
		vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		float a = INSTANCE_CUSTOM.x;
		// (pulled toward the camera by half its size: a billow on the ground isn't cut by it)
		vec3 to_cam = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
		vec4 at = vec4(MODEL_MATRIX[3].xyz + normalize(to_cam) * min(sc.x * 0.5, length(to_cam) * 0.5), 1.0);
		mat4 m = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), at);
		m = m * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * m * mat4(vec4(sc.x, 0.0, 0.0, 0.0), vec4(0.0, sc.y, 0.0, 0.0), vec4(0.0, 0.0, sc.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	vec2 q = c * 1.3 + v_seed * 23.0;
	float n = vnoise(q * 1.5 + v_age * 0.6) * 0.6 + vnoise(q * 3.6 - v_age * 0.9) * 0.4;
	float a = smoothstep(1.0, 0.15, length(c) + (n - 0.5) * 1.2) * (0.5 + n * 0.7) * smoothstep(1.0, 0.6, length(c));   // (nothing at the quad's edge)
	ALBEDO = COLOR.rgb * (0.8 + n * 0.35);
	BACKLIGHT = ALBEDO * 0.7;   // (light through the cloud: lit from behind too)
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	NORMAL = normalize(NORMAL + vec3(c * 0.6, 0.0));
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
