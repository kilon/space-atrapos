// A planet's sea (CosmosPlanet): a sphere at its radius - water (waves, the
// sun's glint, darker out of the shallows), an ice sheet or a lava sea.
shader_type spatial;
render_mode cull_back;

uniform int kind = 1;                    // 1 water, 2 ice, 3 lava
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float radius = 3000.0;
uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform vec4 shallow : source_color = vec4(0.15, 0.45, 0.65, 1.0);
uniform vec4 deep : source_color = vec4(0.05, 0.1, 0.35, 1.0);
uniform vec4 ice : source_color = vec4(0.85, 0.92, 1.0, 1.0);
uniform vec4 lava : source_color = vec4(1.0, 0.4, 0.05, 1.0);
uniform vec4 lava_hot : source_color = vec4(1.0, 0.9, 0.4, 1.0);

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX * radius;      // (a unit sphere, scaled: metres)
}

void fragment() {
	vec3 up = normalize(v_obj);
	float dist = length(VERTEX);
	float near = 1.0 - smoothstep(200.0, 2500.0, dist);
	float big = texture(noise_tex, up * 3.0).r;
	if (kind == 1) {
		vec3 p = v_obj / 37.0 + vec3(TIME * 0.05, 0.0, TIME * 0.03);
		vec3 q = v_obj / 11.0 - vec3(0.0, TIME * 0.07, TIME * 0.04);
		vec3 w = vec3(texture(noise_tex, p).r, texture(noise_tex, p + 0.31).r, texture(noise_tex, q).r) - 0.5;
		vec3 wn = normalize(up + w * 0.25 * near);
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		ALBEDO = mix(deep.rgb, shallow.rgb, 0.35 + 0.3 * big) * (1.0 - fres * 0.4) + vec3(0.25, 0.35, 0.45) * fres;
		ROUGHNESS = 0.12;
		SPECULAR = 0.6;
	} else if (kind == 2) {
		float n = texture(noise_tex, v_obj / 60.0).r;
		ALBEDO = ice.rgb * (0.78 + 0.25 * n) * mix(vec3(0.85, 0.92, 1.0), vec3(1.0), big);
		ROUGHNESS = 0.35;
		SPECULAR = 0.4;
	} else {
		vec3 p = v_obj / 90.0 + vec3(0.0, TIME * 0.02, 0.0);
		float n = texture(noise_tex, p).r * 0.6 + texture(noise_tex, v_obj / 17.0).r * 0.4;
		float crust = smoothstep(0.45, 0.62, n);
		ALBEDO = mix(lava.rgb * 0.4, vec3(0.07, 0.05, 0.04), crust);
		EMISSION = mix(lava_hot.rgb * 2.6, lava.rgb * 0.5, crust) * (0.7 + 0.5 * big);
		ROUGHNESS = 0.8;
	}
}

void light() {
	vec3 L = normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz);
	float d = clamp(dot(NORMAL, L), 0.0, 1.0);
	DIFFUSE_LIGHT += d * ATTENUATION * LIGHT_COLOR / PI;
	if (kind != 3) {
		vec3 H = normalize(L + VIEW);
		float s = pow(clamp(dot(NORMAL, H), 0.0, 1.0), kind == 1 ? 180.0 : 40.0) * (kind == 1 ? 2.5 : 0.4);
		SPECULAR_LIGHT += s * d * ATTENUATION * LIGHT_COLOR;
	}
}
