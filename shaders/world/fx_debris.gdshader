// Fx's debris (CPUParticles3D - data/effects.json): small solid pieces - hull
// shards, rock chips - lit like the ships (metal, rough), tumbling (each piece
// turned round an axis of its own by its angle), glowing with heat by COLOR
// (the emitter's colour ramp: white-hot to dark as it cools).
shader_type spatial;
render_mode cull_back, shadows_disabled;

uniform vec4 albedo : source_color = vec4(0.2, 0.2, 0.22, 1.0);
uniform float metallic = 0.6;
uniform float roughness = 0.55;

mat3 turn(vec3 axis, float a) {
	float s = sin(a);
	float c = cos(a);
	float oc = 1.0 - c;
	return mat3(vec3(oc * axis.x * axis.x + c, oc * axis.x * axis.y + axis.z * s, oc * axis.z * axis.x - axis.y * s),
		vec3(oc * axis.x * axis.y - axis.z * s, oc * axis.y * axis.y + c, oc * axis.y * axis.z + axis.x * s),
		vec3(oc * axis.z * axis.x + axis.y * s, oc * axis.y * axis.z - axis.x * s, oc * axis.z * axis.z + c));
}

void vertex() {
	float s = float(INSTANCE_ID);
	vec3 axis = normalize(vec3(fract(s * 0.754877) - 0.5, fract(s * 0.569840) - 0.5, fract(s * 0.4142) - 0.5) + vec3(0.001, 0.0, 0.0));
	mat3 r = turn(axis, INSTANCE_CUSTOM.x + s);
	VERTEX = r * VERTEX;
	NORMAL = r * NORMAL;
}

void fragment() {
	ALBEDO = albedo.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	EMISSION = COLOR.rgb * COLOR.a;
}
