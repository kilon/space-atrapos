shader_type spatial;
// The 3D game's characters (CosmosModels: a model's parts merged, their
// looks in the vertices): physically based - COLOR the albedo, CUSTOM0 =
// metallic, roughness, emission strength (glowing parts) - one draw.
render_mode cull_back;

varying vec4 v_look;
varying vec3 v_obj;

void vertex() {
	v_look = CUSTOM0;
	v_obj = VERTEX;
}

float h(vec3 p) {
	return fract(sin(dot(floor(p), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	float wear = mix(h(v_obj * 60.0), h(v_obj * 22.0 + 11.0), 0.5);
	ALBEDO = COLOR.rgb * (0.94 + 0.08 * wear);
	METALLIC = v_look.x;
	ROUGHNESS = clamp(v_look.y + (wear - 0.5) * 0.12, 0.05, 1.0);
	EMISSION = COLOR.rgb * v_look.z;
}
