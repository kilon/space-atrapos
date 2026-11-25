shader_type spatial;
// The 3D game's characters (CosmosModels: a model's parts merged, their
// looks in the vertices): physically based - COLOR the albedo, CUSTOM0 =
// metallic, roughness, emission strength (glowing parts), recolour slot;
// CUSTOM1 = the vertex at rest (model space, m) and its normal's up - one draw.
// Worn by use, from the rest pose (so it stays put on the parts as they move):
// grime low on the legs and in blotches, dust on what faces up, paint chipped
// and scratched to the bare metal on the painted parts. Lit parts kept clean.
// Three lookups of the shared noise (Cosmos.noise_ready); without it, a cheap
// value noise stands in.
render_mode cull_back;
stencil_mode write, compare_always, 1;   // (marks where a character is: the scanned veins' hologram never drawn over one - vein_holo)

// Recolouring (the towns' people): the parts of slot 1 (armour), 2 (accent),
// 3 (glow) - CUSTOM0.w - take these colours (linear), as much as their alpha.
uniform vec4 recolor_main = vec4(0.0);
uniform vec4 recolor_accent = vec4(0.0);
uniform vec4 recolor_glow = vec4(0.0);

uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform float has_noise = 0.0;      // (1 once noise_tex is given)
uniform float weathering = 1.0;     // (0 factory new .. 1 in service)

varying vec4 v_look;
varying vec4 v_rest;

void vertex() {
	v_look = CUSTOM0;
	v_rest = CUSTOM1;
}

float h3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// The shared noise (4 features a unit, about 0.5 +- 0.25), or a value noise like it.
float nz(vec3 p) {
	if (has_noise > 0.5) {
		return texture(noise_tex, p).r;
	}
	vec3 q = p * 4.0;
	vec3 i = floor(q);
	vec3 f = q - i;
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y);
	return 0.5 + (mix(a, b, f.z) - 0.5) * 0.6;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
	vec4 rc = v_look.w > 2.5 ? recolor_glow : (v_look.w > 1.5 ? recolor_accent : (v_look.w > 0.5 ? recolor_main : vec4(0.0)));
	float ref = v_look.w > 2.5 ? 0.6 : (v_look.w > 1.5 ? 0.17 : 0.78);   // (each slot's brightest part: its shades kept)
	base = mix(base, rc.rgb * clamp(lum / ref, 0.3, 1.3), rc.a);
	vec3 lit = base;
	float metal = v_look.x;
	float rough = v_look.y;

	vec3 p = v_rest.xyz;
	float up = v_rest.w;
	float k = weathering * (1.0 - step(0.01, v_look.z));       // (lit parts: clean)
	float painted = 1.0 - smoothstep(0.35, 0.6, metal);
	float near = clamp(1.4 - length(fwidth(p)) * 60.0, 0.0, 1.0);   // (the fine wear faded out with distance: no shimmer)

	float big = nz(p * 0.8 + vec3(3.1, 0.7, 5.3));
	float fine = nz(p * 13.0 + vec3(1.3, 7.7, 0.4));
	// scratches: the high tops of a noise stretched thin (slanting), where the wear is
	vec3 sp = vec3(dot(p, vec3(0.8, 0.5, 0.33)) * 5.0, dot(p, vec3(-0.5, 0.8, 0.33)) * 60.0, p.z * 5.0);
	float sn = nz(sp + vec3(9.2, 2.1, 6.6));
	float scratch = smoothstep(0.75, 0.8, sn) * smoothstep(0.55, 0.68, big) * near * k;

	// grime: up from the feet, in blotches, under overhangs
	float low = 1.0 - smoothstep(0.04, 0.9, p.y);
	float splash = smoothstep(0.35, 0.72, big * 0.6 + fine * 0.4 + low * 0.3);
	float grime = low * low * (0.3 + 0.7 * splash) + smoothstep(0.55, 0.75, big) * 0.22 + (1.0 - smoothstep(-0.8, 0.1, up)) * 0.2;
	grime = clamp(grime, 0.0, 1.0) * k;
	base *= mix(vec3(1.0), vec3(0.4, 0.35, 0.29), grime);
	rough = mix(rough, 0.92, grime * 0.45);
	metal *= 1.0 - grime * 0.35;

	// dust settled on what faces up
	float dust = smoothstep(0.35, 0.95, up) * (0.3 + 0.7 * big) * 0.2 * k;
	base = mix(base, vec3(0.34, 0.3, 0.25), dust);
	rough = mix(rough, 0.9, dust);

	// paint chipped to the metal (more of it low down, where the knocks are), a dark rim round each chip
	float cv = fine + (big - 0.5) * 0.35 + low * 0.06;
	float chip = smoothstep(0.745, 0.765, cv) * painted * near * k;
	float rim = (smoothstep(0.715, 0.745, cv) - chip) * painted * near * k;
	base *= 1.0 - max(rim, 0.0) * 0.35;
	base = mix(base, vec3(0.17, 0.165, 0.16), chip);
	metal = mix(metal, 0.6, chip);
	rough = mix(rough, 0.58, chip);

	// scratches: bare metal through paint, brighter on metal
	base = mix(base, mix(base * 1.15, vec3(0.26, 0.255, 0.245), painted), scratch * 0.6);
	metal = mix(metal, 0.7, scratch * painted * 0.6);
	rough = mix(rough, 0.45, scratch * 0.5);

	// a little unevenness in every surface
	base *= 1.0 + ((fine - 0.5) * 0.12 + (big - 0.5) * 0.16) * k;
	rough = clamp(rough + (fine - 0.5) * 0.1 * k, 0.05, 1.0);

	ALBEDO = base;
	METALLIC = clamp(metal, 0.0, 1.0);
	ROUGHNESS = rough;
	EMISSION = lit * v_look.z;
}
