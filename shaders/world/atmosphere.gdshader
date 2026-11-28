// A planet's atmosphere (CosmosPlanet): a shell drawn from the inside (its
// far side), each pixel working out the stretch of air its view ray crosses -
// from the camera (or where the ray enters the shell) to the ground, the
// first thing in the depth buffer, or out of the shell - in four samples of a
// density thinning with height, each lit by the star (golden, orange, red where
// the light grazes - sunrise, sunset: a glow round the sun, a rosy band opposite). The light it scatters is added; the air's thickness dims what's
// behind (stars hide in a day sky). So: a halo round the planet from space,
// a sky from the ground, haze over distant hills.
shader_type spatial;
render_mode unshaded, cull_front, depth_test_disabled, depth_draw_never, blend_premul_alpha, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec4 tint : source_color = vec4(0.45, 0.7, 1.0, 1.0);
uniform float strength = 0.6;
uniform float r_planet = 3000.0;
uniform float r_atmo = 3300.0;

void fragment() {
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 c = NODE_POSITION_WORLD;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rd = normalize(wp - ro);
	float depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth * 2.0 - 1.0;   // (the web's renderer: OpenGL's depth, -1..1 - raw, the ground read as at the eye and the sky came out black)
#endif
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_d = length(vpos.xyz / vpos.w);
	vec3 oc = ro - c;
	float b = dot(oc, rd);
	float cc = dot(oc, oc) - r_atmo * r_atmo;
	float disc = b * b - cc;
	if (disc <= 0.0) discard;
	float sq = sqrt(disc);
	float t0 = max(-b - sq, 0.0);
	float t1 = -b + sq;
	float cp = dot(oc, oc) - r_planet * r_planet;
	float dp = b * b - cp;
	if (dp > 0.0) {
		float tp = -b - sqrt(dp);
		if (tp > 0.0) t1 = min(t1, tp);
	}
	t1 = min(t1, scene_d);
	if (t1 <= t0) discard;
	float H = r_atmo - r_planet;
	float seg = (t1 - t0) / 4.0;
	float dens = 0.0;
	vec3 light = vec3(0.0);
	float mu = dot(rd, sun_dir);   // (the view's angle to the sun)
	// (in the air, the sunset's colours are the sun's height where you stand - a small world's
	// sky a few km off is in another hour; from space, each place's own: the ring of dusk)
	float inside = 1.0 - smoothstep(r_planet + H * 0.6, r_atmo, length(oc));
	float warm_eye = 1.0 - smoothstep(-0.06, 0.32, dot(normalize(oc), sun_dir));
	float hz = mix(1.0, 1.0 - smoothstep(-0.05, 0.55, dot(rd, normalize(oc))), inside);   // (1 low round the sky, 0 overhead)
	// (forward scattering: a glow round the sun - Henyey-Greenstein, g 0.72)
	float mie = 0.0218 / pow(1.5184 - 1.44 * mu, 1.5);
	for (int i = 0; i < 4; i++) {
		vec3 p = oc + rd * (t0 + seg * (float(i) + 0.5));
		float r = length(p);
		float alt = clamp((r - r_planet) / H, 0.0, 1.0);
		float d = exp(-alt * 4.0) * seg / H;
		float sd = dot(p / r, sun_dir);
		float lit = smoothstep(-0.18, 0.25, sd);
		// The light where it lands: the lower the sun, the more air it came through -
		// white at noon, golden, orange, the last of it deep red.
		float warm = mix(1.0 - smoothstep(-0.02, 0.4, sd), warm_eye, inside);
		vec3 sunc = mix(vec3(1.0, 0.97, 0.92), vec3(1.0, 0.36, 0.08), warm);
		sunc = mix(sunc, vec3(0.8, 0.18, 0.14), smoothstep(0.75, 1.0, warm));
		// The sky's own blue, dimmer and deeper as it falls; the sun's glow, golden low;
		// opposite it at twilight, a rosy band.
		// Overhead the blue deepens; low round the sky a band - orange, gold towards the
		// sun, rose opposite it; the sun's glow.
		vec3 col = mix(tint.rgb, vec3(0.14, 0.2, 0.5), warm * 0.85) * mix(1.0, 0.75, warm);
		col = mix(col, sunc * 0.8, warm * hz * (0.25 + 0.75 * smoothstep(-0.4, 0.9, mu)));   // (low towards the sun: orange, gold)
		col = mix(col, vec3(0.78, 0.38, 0.5), warm * hz * smoothstep(0.1, -0.8, mu) * 0.55);  // (low opposite: rose)
		col += sunc * mie * mix(0.3, 0.45, warm);
		dens += d;
		light += col * lit * d;
	}
	float ext = 1.0 - exp(-dens * strength * 1.6);
	vec3 sc = light * strength * 1.1;
	sc = sc / (1.0 + sc * 0.6);
	ALBEDO = sc;
	ALPHA = clamp(ext * 0.85, 0.0, 1.0) * clamp(length(light) / max(dens * length(tint.rgb), 1e-4) + 0.1, 0.0, 1.0);
}
