// A planet's ground in the 3D game (CosmosPlanet's terrain patches): coloured
// by height, slope, latitude and a 3D noise (the planet's PlanetGen palette -
// the same colours as its 2D look); lit by its star from `sun_dir` (each
// planet has its own: the sun is a point, the scene's one light follows the
// ship), shadows from that light near the ship.
shader_type spatial;
render_mode cull_back, specular_disabled;

instance uniform vec3 patch_centre;      // the patch's centre, planet-local
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float radius = 3000.0;
uniform float amp = 80.0;
uniform int sea = 0;                     // 0 none, 1 water, 2 ice, 3 lava
uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform vec4 land_low : source_color = vec4(0.35, 0.3, 0.22, 1.0);
uniform vec4 land_mid : source_color = vec4(0.5, 0.4, 0.3, 1.0);
uniform vec4 land_high : source_color = vec4(0.3, 0.28, 0.27, 1.0);
uniform vec4 land_peak : source_color = vec4(0.75, 0.73, 0.7, 1.0);
uniform float biome = 0.0;
uniform vec4 biome_color : source_color = vec4(0.7, 0.35, 0.15, 1.0);
uniform float ice_cover = 0.0;
uniform vec4 ice_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float lava = 0.0;
uniform vec4 lava_color : source_color = vec4(1.0, 0.3, 0.05, 1.0);
uniform vec4 lava_hot : source_color = vec4(1.0, 0.85, 0.35, 1.0);
uniform vec4 water_shallow : source_color = vec4(0.1, 0.5, 0.6, 1.0);
uniform vec4 water_deep : source_color = vec4(0.02, 0.1, 0.25, 1.0);

varying vec3 v_local;
varying float v_h;

void vertex() {
	v_local = VERTEX + patch_centre;
	v_h = UV.x;
}

float nz(vec3 p) {
	return texture(noise_tex, p).r;
}

vec3 grad4(vec3 a, vec3 b, vec3 c, vec3 d, float t) {
	if (t < 0.33) return mix(a, b, t / 0.33);
	if (t < 0.7) return mix(b, c, (t - 0.33) / 0.37);
	return mix(c, d, (t - 0.7) / 0.3);
}

void fragment() {
	vec3 up = normalize(v_local);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - clamp(dot(wn, up), 0.0, 1.0);
	float dist = length(VERTEX);
	// Noise at three scales: the planet's (biomes), a field's, underfoot
	// (faded out with distance: no shimmer).
	float n0 = nz(up * 2.3);
	float n1 = nz(v_local / 420.0);
	float n2 = nz(v_local / 23.0);
	float near = 1.0 - smoothstep(150.0, 900.0, dist);
	float hl;
	vec3 col;
	if (sea > 0) {
		// Sand on the shores, then the land's own colours up to the peaks.
		hl = clamp(v_h / (amp * 1.8) + (n0 - 0.5) * 0.22 + (n1 - 0.5) * 0.1, 0.0, 1.0);
		col = hl < 0.5 ? mix(land_mid.rgb, land_high.rgb, hl / 0.5) : mix(land_high.rgb, land_peak.rgb, smoothstep(0.5, 0.95, hl));
		float sand = 1.0 - smoothstep(amp * 0.015, amp * 0.05, v_h + (n2 - 0.5) * amp * 0.03 * near + (n1 - 0.5) * amp * 0.03);
		col = mix(col, land_low.rgb, sand);
	} else {
		hl = clamp((v_h + amp) / (amp * 3.0) + (n0 - 0.5) * 0.25 + (n1 - 0.5) * 0.12, 0.0, 1.0);
		col = grad4(land_low.rgb, land_mid.rgb, land_high.rgb, land_peak.rgb, hl);
	}
	if (biome > 0.0) {
		float bp = smoothstep(0.48, 0.6, nz(up * 1.4 + 3.7));
		col = mix(col, biome_color.rgb * (0.8 + 0.4 * n1), bp * biome * (1.0 - hl * 0.6));
	}
	// Bare rock on the steep slopes, the ground's grain close up.
	vec3 rock = mix(land_high.rgb, land_low.rgb, 0.4) * (0.7 + 0.4 * n1);
	col = mix(col, rock, smoothstep(0.25, 0.55, slope + (n2 - 0.5) * 0.15 * near));
	col *= 0.82 + 0.36 * mix(n1, n2, near);
	// Under the sea: its floor, darker with depth.
	if (sea == 1 && v_h < 0.0) {
		col = mix(col, water_deep.rgb * 0.6, clamp(-v_h / (amp * 0.5), 0.0, 0.8));
	}
	// Snow on the heights and the poles.
	if (ice_cover > 0.0 || sea == 2) {
		float cover = max(ice_cover, sea == 2 ? 0.35 : 0.0);
		float snow = smoothstep(0.0, 0.1, hl - (1.0 - cover) + (n1 - 0.5) * 0.3);
		float polar = smoothstep(0.0, 0.06, abs(up.y) - (1.0 - cover * 0.7) + (n0 - 0.5) * 0.25);
		float ice = max(snow * (1.0 - smoothstep(0.35, 0.6, slope)), polar);
		col = mix(col, ice_color.rgb * (0.85 + 0.2 * n2), ice);
	}
	vec3 emit = vec3(0.0);
	if (lava > 0.0) {
		float lr = 1.0 - abs(nz(up * 3.1 + 1.3) * 2.0 - 1.0);
		float crack = smoothstep(0.9, 0.98, lr) * (1.0 - smoothstep(0.0, 0.4, hl));
		float m = clamp(crack * lava, 0.0, 1.0);
		col = mix(col, lava_color.rgb * 0.3, m);
		emit = mix(lava_color.rgb, lava_hot.rgb, m * m) * m * 2.0;
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	EMISSION = emit;
}

void light() {
	vec3 L = normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz);
	float d = clamp(dot(NORMAL, L), 0.0, 1.0);
	DIFFUSE_LIGHT += d * ATTENUATION * LIGHT_COLOR / PI;
}
