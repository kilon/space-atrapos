// A gas giant in the 3D game (CosmosPlanet): bands of cloud from its PlanetGen
// colours, turbulent (the bands warped by the 3D noise), a great storm, slowly
// turning; lit by its star.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform vec4 gas_a : source_color = vec4(0.85, 0.75, 0.6, 1.0);
uniform vec4 gas_b : source_color = vec4(0.6, 0.45, 0.3, 1.0);
uniform vec4 gas_c : source_color = vec4(0.95, 0.9, 0.8, 1.0);
uniform vec4 gas_d : source_color = vec4(0.4, 0.5, 0.65, 1.0);
uniform float band_count = 7.0;
uniform float band_turb = 0.5;
uniform float storm = 0.0;
uniform vec2 storm_pos = vec2(0.6, -0.35);
uniform float storm_size = 0.18;
uniform vec4 storm_color : source_color = vec4(0.85, 0.4, 0.15, 1.0);
uniform float seed = 0.0;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

float nz(vec3 p) {
	return texture(noise_tex, p).r;
}

void fragment() {
	vec3 b0 = normalize(v_obj);
	float a = TIME * 0.006;
	vec3 g = vec3(cos(a) * b0.x - sin(a) * b0.z, b0.y, sin(a) * b0.x + cos(a) * b0.z);
	vec3 tq = g * vec3(1.2, 3.6, 1.2) + vec3(seed * 0.01);
	float w1 = nz(tq);
	float w2 = nz(tq * 2.3 + vec3(w1 * 1.5, 0.0, w1)) * 0.65 + nz(tq * 6.0) * 0.35;
	float lat = g.y + band_turb * 0.14 * (w2 - 0.5);
	float lon = atan(g.z, g.x);
	float glat = asin(clamp(g.y, -1.0, 1.0));
	float sd = 99.0;
	vec2 er = vec2(0.0);
	if (storm > 0.0) {
		float dl = mod(lon - storm_pos.x + PI, TAU) - PI;
		vec2 e = vec2(dl * cos(glat) * 0.55, glat - storm_pos.y);
		sd = length(e) / storm_size;
		if (sd < 1.6) {
			float k = max(1.0 - sd / 1.6, 0.0);
			float sang = storm * 5.0 * k * k;
			er = mat2(vec2(cos(sang), sin(sang)), vec2(-sin(sang), cos(sang))) * e;
			lat = sin(storm_pos.y + er.y) + band_turb * 0.1 * (w2 - 0.5);
		}
	}
	float v = lat * band_count;
	float b1 = 0.5 + 0.5 * sin(v * PI + seed);
	float b2 = 0.5 + 0.5 * sin(v * 1.37 * PI + seed * 1.7);
	float fine = nz(vec3(v * 0.9, seed * 0.01, w1 * 0.4));
	vec3 col = mix(gas_a.rgb, gas_b.rgb, smoothstep(0.15, 0.85, b1));
	col = mix(col, gas_c.rgb, smoothstep(0.55, 0.92, b2) * 0.85);
	col = mix(col, gas_d.rgb, smoothstep(0.55, 0.8, fine) * 0.65);
	col *= 0.86 + 0.28 * nz(g * vec3(1.0, 14.0, 1.0) + w2);
	if (storm > 0.0 && sd < 1.2) {
		float sc = smoothstep(1.15, 0.35, sd);
		float sw = nz(vec3(er / storm_size * 0.6, seed * 0.01 + 0.5));
		vec3 swirl = storm_color.rgb * (0.6 + 0.75 * sw);
		col = mix(col, swirl, sc * storm * 0.9);
	}
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float lit = smoothstep(-0.12, 0.6, dot(wn, sun_dir));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = col * (0.03 + 0.97 * lit) * (1.0 - rim * 0.35);
}
