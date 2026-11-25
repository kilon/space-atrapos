shader_type spatial;
// The planet map's globe (PlanetMapPage): its real ground (PlanetShape - the
// heights raised, the colours in the vertices), lit from over the viewer's
// shoulder (the relief reads all round), a grid every 30 degrees, and the fog
// of war (PlanetFog: fog_tex, longitude x latitude - 0 never seen .. 1 seen):
// the unseen ground a dark haze with only its shape faintly shown. Seas and
// lava lakes coloured here, by the height (UV.x: metres / amp, interpolated -
// smooth shores, not the mesh's grid).
render_mode unshaded, fog_disabled, shadows_disabled;

uniform sampler2D fog_tex : filter_linear, repeat_enable;
uniform float has_fog = 1.0;
uniform vec4 haze_col : source_color = vec4(0.03, 0.05, 0.08, 1.0);
uniform vec4 grid_col : source_color = vec4(0.5, 0.9, 1.0, 1.0);
uniform float sea_kind = 0.0;    // 1 water, 3 lava (PlanetShape.sea)
uniform vec4 sea_a : source_color = vec4(0.15, 0.45, 0.6, 1.0);   // shallow (lava: hot)
uniform vec4 sea_b : source_color = vec4(0.03, 0.12, 0.3, 1.0);   // deep (lava: dark)
uniform float sea_depth = 0.4;   // (amps down to the deepest colour)

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 d = normalize(v_local);
	float lat = asin(clamp(d.y, -1.0, 1.0));
	float lon = atan(d.x, d.z);
	vec2 uv = vec2((lon + PI) / TAU, (PI * 0.5 - lat) / PI);
	float seen = has_fog > 0.5 ? texture(fog_tex, uv).r : 1.0;
	seen = smoothstep(0.25, 0.75, seen);
	vec3 l = normalize(vec3(-0.45, 0.6, 0.75));
	float nl = max(dot(NORMAL, l), 0.0);
	vec3 base = COLOR.rgb;
	if (sea_kind > 0.5) {
		float hn = UV.x;
		float fh = max(fwidth(hn), 1e-4);
		float wet = 1.0 - smoothstep(-fh, fh, hn);
		base = mix(base, mix(sea_a.rgb, sea_b.rgb, clamp(-hn / sea_depth, 0.0, 1.0)), wet);
	}
	vec3 lit = base * (0.3 + 0.95 * nl);
	float shape = 0.35 + 0.65 * nl;
	vec3 col = mix(haze_col.rgb * (0.6 + 0.8 * shape), lit, seen);
	// The grid: every 30 degrees (the equator brighter).
	vec2 g = vec2(lon, lat) / radians(30.0);
	vec2 fw = fwidth(g);
	vec2 gl = abs(fract(g - 0.5) - 0.5) / max(fw, vec2(1e-5));
	float line = 1.0 - min(min(gl.x, gl.y), 1.0);
	float eq = 1.0 - min(abs(g.y) / max(fw.y, 1e-5), 1.0);
	col = mix(col, grid_col.rgb, line * mix(0.1, 0.22, 1.0 - seen) + eq * 0.18);
	ALBEDO = col;
}
