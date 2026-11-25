// A planet's atmosphere (CosmosPlanet): a shell drawn from the inside (its
// far side), each pixel working out the stretch of air its view ray crosses -
// from the camera (or where the ray enters the shell) to the ground, the
// first thing in the depth buffer, or out of the shell - in four samples of a
// density thinning with height, each lit by the star (orange where the light
// grazes). The light it scatters is added; the air's thickness dims what's
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
	for (int i = 0; i < 4; i++) {
		vec3 p = oc + rd * (t0 + seg * (float(i) + 0.5));
		float r = length(p);
		float alt = clamp((r - r_planet) / H, 0.0, 1.0);
		float d = exp(-alt * 4.0) * seg / H;
		float sd = dot(p / r, sun_dir);
		float lit = smoothstep(-0.18, 0.25, sd);
		vec3 col = mix(vec3(1.0, 0.45, 0.2), tint.rgb, smoothstep(0.0, 0.45, sd));
		dens += d;
		light += col * lit * d;
	}
	float ext = 1.0 - exp(-dens * strength * 1.6);
	vec3 sc = light * strength * 1.1;
	sc = sc / (1.0 + sc * 0.6);
	ALBEDO = sc;
	ALPHA = clamp(ext * 0.85, 0.0, 1.0) * clamp(length(light) / max(dens * length(tint.rgb), 1e-4) + 0.1, 0.0, 1.0);
}
