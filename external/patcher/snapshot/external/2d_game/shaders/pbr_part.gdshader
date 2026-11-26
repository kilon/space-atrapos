shader_type spatial;
// The 3D characters' surfaces, photoreal (the game's look since 2026-11-21 -
// it was cel shading): physically based - painted armour, bare metal, rubber
// and cloth (metallic / roughness by the part: Stage3D.surface_look), a fine
// wear in the roughness so the light breaks across it, glowing lights.
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float metallic = 0.5;
uniform float roughness = 0.4;
uniform vec3 emission = vec3(0.0);

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

float h(vec3 p) {
	return fract(sin(dot(floor(p), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	vec3 p = v_obj * 60.0;
	float wear = mix(h(p), h(p * 0.37 + 11.0), 0.5);
	ALBEDO = albedo.rgb * (0.94 + 0.08 * wear);
	METALLIC = metallic;
	ROUGHNESS = clamp(roughness + (wear - 0.5) * 0.12, 0.05, 1.0);
	EMISSION = emission;
}
