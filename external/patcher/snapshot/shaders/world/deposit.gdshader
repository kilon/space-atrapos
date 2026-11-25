// Mineral deposits on the planets (CosmosDeposits): one material for them all,
// each instance its own mineral - `tint`, how metallic, how glassy, a faint
// inner glow (instance uniforms: no material per mineral). Ore boulders are
// rock grained by the 3D noise with the metal in veins through it; crystals
// (v_crystal from the mesh's colour: red = 1) are clear-ish and glossy.
shader_type spatial;

uniform sampler3D noise_tex : filter_linear, repeat_enable;
instance uniform vec4 tint : source_color = vec4(0.6, 0.4, 0.3, 1.0);
instance uniform float metal = 0.0;
instance uniform float glow = 0.0;
instance uniform float heat = 0.0;     // (being cut: it glows hot where the beam is)

varying vec3 v_obj;
varying float v_crystal;

void vertex() {
	v_obj = VERTEX;
	v_crystal = COLOR.r;
}

void fragment() {
	float n = texture(noise_tex, v_obj * 0.55).r * 0.6 + texture(noise_tex, v_obj * 2.1).r * 0.4;
	vec3 col;
	float rough;
	float met;
	if (v_crystal > 0.5) {
		// (a crystal: its colour deep in the facets, lighter at the edges)
		col = tint.rgb * (0.75 + 0.4 * n);
		rough = 0.12 + 0.1 * n;
		met = metal * 0.6;
		EMISSION = tint.rgb * glow * (0.5 + n);
	} else {
		// (an ore boulder: rock, the metal showing in veins)
		vec3 rock = vec3(0.34, 0.31, 0.28) * (0.6 + 0.7 * n);
		float vein = smoothstep(0.52, 0.6, texture(noise_tex, v_obj * 0.9 + vec3(3.1)).r);
		col = mix(rock, tint.rgb, vein);
		rough = mix(0.9, 0.35, vein);
		met = metal * vein;
		EMISSION = tint.rgb * glow * vein;
	}
	// (where it's being cut it glows hot: the low parts, near the ground, most)
	EMISSION += vec3(1.0, 0.42, 0.12) * heat * 0.5 * (0.4 + 0.6 * n);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = met;
	SPECULAR = 0.5;
}
