// A planet's plants (CosmosFlora, scattered by CosmosPlanet): vertex colours,
// a glow where a species glows (UV.x: crystals, some fungi), swaying in the
// wind - more the higher up the plant (UV.y: the vertex's height), each plant
// in its own rhythm (its place).
shader_type spatial;
render_mode cull_disabled;

uniform float wind = 1.0;

void vertex() {
	vec3 at = MODEL_MATRIX[3].xyz;
	float ph = dot(at, vec3(0.13, 0.07, 0.11));
	float k = UV.x > 0.9 ? 0.0 : wind * 0.04 * pow(max(UV.y, 0.0), 1.3);
	VERTEX.x += sin(TIME * 1.7 + ph) * k;
	VERTEX.z += cos(TIME * 1.3 + ph * 1.7) * k * 0.7;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
	EMISSION = COLOR.rgb * UV.x * 1.4;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;     // (grass blades: both sides)
	}
}
