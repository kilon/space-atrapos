shader_type spatial;
// Cel shading for the 3D characters (Stage3D): the light makes two hard tones -
// lit (the colour itself) and shade (the colour times `shade_tone`) - and, where
// it hits square, a brighter third (`hi`). As the Blender kit's toon material
// (external/blender/automaton/kit.py: mat_toon), so the model in the game looks
// like its rendered sprites.
render_mode cull_back, specular_disabled, ambient_light_disabled;

uniform vec3 color : source_color = vec3(0.9, 0.85, 0.75);
uniform vec3 shade_tone = vec3(0.3, 0.3, 0.35);   // (linear: what the lit colour is multiplied by in shade)
uniform float hi = 0.0;
uniform float edge = 0.4;                          // (the light's cosine where lit begins)

void fragment() {
	ALBEDO = color;
}

void light() {
	float n = dot(NORMAL, LIGHT);
	vec3 tone = n > edge ? vec3(1.0) : shade_tone;
	if (hi > 0.0 && n > 0.93) {
		tone = vec3(1.0 + hi);
	}
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, tone);
}
