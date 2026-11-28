// Under the sea (CosmosUnderwater), pass 2 of 2, added over pass 1: the
// water's own light along each view ray (it scatters the sunlight as deep
// as it is - the murk), light shafts from the surface (a few dithered steps
// through the light's pattern), and the surface itself seen from below
// where the ray reaches it first: the sky in Snell's window, bright at its
// rim, the sun's glare through it, and beyond it the deep mirrored (total
// internal reflection) - the surface rippling.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_add, fog_disabled, shadows_disabled;

#include "res://shaders/world/underwater.gdshaderinc"
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;   // (what stands over the water: seen through the window)
#endif

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 rd;
	vec3 vpos;
	float dist;
	float t_s;
	uw_ray(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, rd, vpos, dist, t_s);
	float up_k = dot(rd, up);
	float sunk = uw_sun();
	vec3 col = vec3(0.0);
	float d_end;
	float z_end;
	if (t_s < dist && up_k > 0.0) {
		// The underside of the surface: Snell's window, total internal reflection outside it.
		d_end = t_s;
		z_end = 0.0;
		vec3 hs = eye_rel + rd * t_s;
		vec3 n = normalize(hs);
		vec2 sp = uw_plane(hs);
		vec2 rip = vec2(texture(noise_tex, vec3(sp * 0.09, TIME * 0.05)).r, texture(noise_tex, vec3(sp * 0.09 + 0.5, TIME * 0.05 + 0.3)).r) - 0.5;
		rip += (vec2(texture(noise_tex, vec3(sp * 0.37, TIME * 0.11 + 0.6)).r, texture(noise_tex, vec3(sp * 0.37 + 0.27, TIME * 0.11 + 0.9)).r) - 0.5) * 0.5;   // (and its small ripples)
		vec3 wn = normalize(n + (axis_u * rip.x + axis_v * rip.y) * 0.16);
		float cosi = dot(rd, wn);
		float win = smoothstep(0.64, 0.70, cosi);
		vec3 out_d = normalize(refract(rd, -wn, 1.333) + vec3(1e-5));
		float sd = max(dot(out_d, sun_dir), 0.0);
		float glare = pow(sd, 90.0) * 6.0 + pow(sd, 8.0) * 0.6;
		vec3 sky_c = sky.rgb * (0.25 + 0.95 * sunk) + vec3(1.0, 0.97, 0.9) * glare * sunk;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
		if (dist < 1e5) {   // (something over the water there - the shore, a hull, the trees: seen through it, bent by its waves)
			vec2 wob = rip * 0.035 / (1.0 + t_s * 0.05);
			sky_c = mix(sky_c, texture(screen_tex, clamp(SCREEN_UV + wob, 0.0, 1.0)).rgb * (0.7 + 0.3 * sunk), 0.85);
		}
#endif
		float rim = exp(-pow((cosi - 0.665) * 28.0, 2.0)) * 0.6;   // (the window's bright edge)
		vec3 below = water.rgb * 0.35 * (0.2 + sunk);               // (outside it: the deep, mirrored)
		col = (mix(below, sky_c, win) + sky_c * rim * 0.5) * exp(-extinct * d_end);
	} else {
		d_end = min(dist, 4000.0);
		z_end = max(radius - length(eye_rel + rd * d_end), 0.0);
	}
	// The water between, lit itself (scattering) as deep as it is.
	vec3 trans = exp(-extinct * d_end);
	vec3 lit = water.rgb * exp(-absorb * mix(eye_depth, z_end, 0.5)) * (0.12 + 0.88 * sunk);
	col += lit * (1.0 - trans);
	// Light shafts from the surface: steps along the ray, each lit as the waves above it focus
	// the sun down along the light (dithered; the pattern drifting) - fading deeper and further.
	float reach = min(d_end, 40.0);
	float jit = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float acc = 0.0;
	float lu = max(dot(light_dir, up), 0.3);
	for (int i = 0; i < 6; i++) {
		float s = (float(i) + jit) * (1.0 / 6.0) * reach;
		float zs = max(eye_depth - up_k * s, 0.0);
		vec3 ps = eye_rel + rd * s + light_dir * (zs / lu);
		vec2 pp = uw_plane(ps);
		float k = smoothstep(0.52, 0.8, texture(noise_tex, vec3(pp * 0.055, TIME * 0.012)).r);
		k *= 0.55 + 0.9 * smoothstep(0.45, 0.75, texture(noise_tex, vec3(pp * 0.16 + 0.3, TIME * 0.02)).r);   // (finer beams within)
		acc += k * exp(-extinct.g * s - absorb.g * zs * 1.3);
	}
	float phase = 0.25 + 2.2 * pow(max(dot(rd, light_dir), 0.0), 5.0);
	col += water.rgb * vec3(0.9, 1.0, 1.0) * (acc * (1.0 / 6.0)) * (reach / 32.0) * phase * sunk * 0.6;
	ALBEDO = col;
}
