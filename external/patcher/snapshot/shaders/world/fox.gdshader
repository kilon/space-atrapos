// The red fox's coat (CosmosFox): soft wrapped light as fur takes it, strands
// running along each part (UV: round it, along it), a rim of light at its edge
// and a little through the thin parts; its colours from COLOR - r white (chin,
// throat, chest, belly, the tail's tip), g black (the stockings, the ears'
// backs, the nose); b an eye: amber, a slit pupil (a: how far toward it); the
// nose (a 0.5) glossy. A flash when hit.
shader_type spatial;
render_mode diffuse_lambert_wrap, cull_back;

uniform vec4 c1 : source_color = vec4(0.85, 0.42, 0.15, 1.0);
uniform vec4 c2 : source_color = vec4(0.95, 0.92, 0.88, 1.0);
uniform float flash = 0.0;
uniform sampler3D noise_tex : filter_linear, repeat_enable;

void fragment() {
	float white = COLOR.r;
	float black = COLOR.g;
	// Fur: fine strands along the part, a coarser clumping, the tips paler.
	float strand = texture(noise_tex, vec3(UV.x * 16.0, UV.y * 2.5, 0.37)).r;
	float clump = texture(noise_tex, vec3(UV.x * 3.0, UV.y * 0.6, 0.71)).r;
	float fur = 0.86 + 0.24 * strand * (0.7 + 0.6 * clump);
	vec3 orange = c1.rgb * mix(0.8, 1.15, clump);
	orange = mix(orange, orange * vec3(0.75, 0.7, 0.65), smoothstep(0.6, 0.8, strand) * 0.4);   // (darker guard hairs)
	vec3 base = mix(orange, c2.rgb, smoothstep(0.2, 0.8, white));
	base = mix(base, vec3(0.035, 0.03, 0.028), smoothstep(0.2, 0.8, black));
	base *= fur;
	float rough = 0.85;
	float spec = 0.25;
	// The nose: black, wet.
	if (black > 0.5 && COLOR.a > 0.4 && COLOR.a < 0.6) {
		base = vec3(0.02);
		rough = 0.25;
		spec = 0.5;
	}
	// The eyes: amber, a black vertical slit, glassy.
	if (COLOR.b > 0.5) {
		float k = COLOR.a;
		vec3 amber = mix(vec3(0.75, 0.45, 0.08), vec3(0.95, 0.7, 0.2), smoothstep(0.5, 0.95, k));
		float slit = smoothstep(0.7, 0.8, k) * (1.0 - smoothstep(0.18, 0.32, abs(cos(UV.x * 6.2832))));
		base = mix(amber * mix(0.4, 1.0, smoothstep(0.3, 0.6, k)), vec3(0.01), slit);
		rough = 0.05;
		spec = 0.7;
	}
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 3.0);
	ALBEDO = base + mix(c1.rgb, c2.rgb, white) * rim * 0.18 * (1.0 - COLOR.b);
	ROUGHNESS = rough;
	SPECULAR = spec;
	BACKLIGHT = mix(c1.rgb, c2.rgb, white) * 0.12 * (1.0 - black);
	EMISSION = vec3(1.0, 0.25, 0.15) * flash;
}
