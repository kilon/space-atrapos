// A planet's cloud layer (CosmosPlanet: three of them - low, thick and dark
// under the weather; mid, heaped; high, thin streaks racing) - a shell above
// its mountains, drifting at its own pace: coverage from the 3D noise at
// three scales (stretched for the streaks), thickened and darkened where the
// weather is (PlanetWeather's cells: their middles, reach, strength, storm),
// lit by the star (gold and rose from below at dawn and dusk), seen from above
// and below.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float cover = 0.5;
uniform float scale = 2.2;
uniform float seed = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform float speed = 1.0;          // (its drift, against the others')
uniform vec3 stretch = vec3(0.55, 1.0, 0.55);   // (its shapes: heaps; streaks long one way)
uniform float soft = 0.16;          // (its edges: crisp heaps, soft veils)
uniform float opacity = 0.92;
uniform float weather_k = 1.0;      // (how much the weather thickens it)
uniform float storm_dark = 0.65;    // (how dark a storm makes it)
uniform vec4 cell_a[8];             // (the weather: middle xyz, reach in radians)
uniform vec4 cell_b[8];             // (strength, wet, snow, storm)

varying vec3 v_obj;
varying vec2 v_w;                   // (the weather under this bit of sky: how thick, how dark - a vertex's, the cells kilometres wide)

void vertex() {
	v_obj = VERTEX;
	vec3 up = normalize(VERTEX);
	v_w = vec2(0.0);
	for (int i = 0; i < 8; i++) {
		vec4 ca = cell_a[i];
		vec4 cb = cell_b[i];
		float k = ca.w > 0.0 ? smoothstep(cos(ca.w * 1.35), cos(ca.w * 0.5), dot(up, ca.xyz)) : 0.0;   // (its clouds overhanging where it rains)
		v_w.x = max(v_w.x, k * (0.35 + 0.65 * cb.x));
		v_w.y = max(v_w.y, k * cb.x * (0.55 + 0.45 * cb.w));
	}
}

void fragment() {
	vec3 up = normalize(v_obj);
	float a = TIME * 0.004 * speed;
	vec3 q = vec3(cos(a) * up.x - sin(a) * up.z, up.y, sin(a) * up.x + cos(a) * up.z);
	vec3 p = q * scale * stretch + vec3(seed * 0.013);
	float n = texture(noise_tex, p).r * 0.62 + texture(noise_tex, p * 3.1 + 0.4).r * 0.28 + texture(noise_tex, p * 9.0).r * 0.1;
	// (the weather over here: thicker, darker under it - a storm's anvil black)
	float wcov = v_w.x;
	float wdark = v_w.y;
	float cv = clamp(cover + wcov * weather_k * 0.75, 0.0, 1.0);
	float thr = mix(0.72, 0.3, cv);
	float c = smoothstep(thr, thr + soft, n);
	c = mix(c, 1.0, smoothstep(0.55, 0.95, wcov * weather_k) * 0.9);   // (under strong weather: one sheet, no gaps - overcast)
	float sd = dot(up, sun_dir);
	float lit = smoothstep(-0.2, 0.4, sd);
	// (by the dawn and the dusk: lit gold and rose from below, the sun's last light - under
	// them, as the sun stands where you are; from above, where they are)
	vec3 eye = CAMERA_POSITION_WORLD - NODE_POSITION_WORLD;
	float shell = length(MODEL_MATRIX[0].xyz);   // (its radius: a unit sphere, scaled)
	float below = 1.0 - smoothstep(0.98, 1.02, length(eye) / max(shell, 1.0));
	float se = mix(sd, dot(normalize(eye), sun_dir), below);
	float glow = exp(-pow((se - 0.03) / 0.14, 2.0));
	vec3 dusk = mix(vec3(1.0, 0.46, 0.2), vec3(0.92, 0.36, 0.48), smoothstep(0.1, -0.1, se));
	vec3 col = mix(tint.rgb, dusk, glow) * (0.06 + 0.94 * max(lit, glow * 0.8)) * (0.85 + 0.3 * n);
	col *= 1.0 - wdark * storm_dark * smoothstep(0.3, 1.0, n + 0.3);   // (heavy with rain: grey, the storm's black)
	ALBEDO = col;
	ALPHA = c * opacity * mix(1.0, 1.08, wcov);
}
