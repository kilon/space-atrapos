// The sea's plants and corals (CosmosUnderwater): vertex colours; kelp and
// sea grass bending with the current and swaying in the swell - more the
// higher up the plant (UV.y: the vertex's height, 0 at its foot, 1 at its
// tip; UV2.x the plant's height), by how supple that part is (UV.x: 1 a
// blade, 0 a coral's stone) - each plant in its own rhythm (its place).
shader_type spatial;
render_mode cull_disabled;

uniform vec3 current = vec3(1.0, 0.0, 0.0);   // world: the flow's way and strength
uniform float swell = 1.0;
uniform vec3 fill = vec3(0.0);                // the water's own light, all round (scattered: the shade's not black)

void vertex() {
	float flex = UV.x;
	float f = clamp(UV.y, 0.0, 1.0);
	float h = UV2.x;
	if (flex > 0.0) {
		vec3 at = MODEL_MATRIX[3].xyz;
		float ph = dot(at, vec3(0.21, 0.13, 0.17));
		mat3 m = mat3(MODEL_MATRIX);
		float s2 = max(dot(m[0], m[0]), 1e-4);
		vec3 cur = (transpose(m) * current) / s2;   // (the current in the plant's own space)
		cur.y = 0.0;
		float amp = flex * h * pow(f, 1.5) * 0.16;
		vec3 sway = cur * (0.7 + 0.3 * sin(TIME * 0.45 + ph + f * 2.0))
			+ vec3(sin(TIME * 0.8 + ph + f * 2.6), 0.0, cos(TIME * 0.63 + ph * 1.3 + f * 2.1)) * 0.45 * swell;
		VERTEX += sway * amp;
		VERTEX.y -= dot(sway, sway) * amp * amp * 0.35 / max(h, 0.2);   // (a bent stalk is a little lower)
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = mix(0.55, 0.85, UV.x);
	SPECULAR = 0.35;
	BACKLIGHT = COLOR.rgb * 0.35 * UV.x;   // (thin blades: lit through)
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
		ALBEDO *= 0.7;   // (a sponge's inside, a blade's underside)
	}
	EMISSION = ALBEDO * fill;
}
