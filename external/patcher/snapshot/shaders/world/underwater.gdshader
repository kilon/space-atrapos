// Under the sea (CosmosUnderwater), pass 1 of 2: drawn over the whole screen
// while the camera is below a sea's surface, multiplying what's there - the
// water's absorption along each view ray (red gone first: blue-green, and
// darker deeper - the sunlight already lost on its way down to each point)
// and the caustics (the surface's light net) on the floor and on whatever
// faces up near you. Where the ray reaches the surface first: nothing kept
// (pass 2, underwater_glow, draws the surface from below and the water's
// own light). Depth buffer only (underwater.gdshaderinc).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mul, fog_disabled, shadows_disabled;

#include "res://shaders/world/underwater.gdshaderinc"

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);   // (a 2 x 2 quad: the whole screen)
}

void fragment() {
	vec3 rd;
	vec3 vpos;
	float dist;
	float t_s;
	uw_ray(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, rd, vpos, dist, t_s);
	vec3 k = vec3(0.0);
	if (!(t_s < dist && dot(rd, up) > 0.0)) {
		float d_end = min(dist, 4000.0);
		vec3 p = eye_rel + rd * d_end;
		float z_end = max(radius - length(p), 0.0);
		k = exp(-absorb * z_end - extinct * d_end);   // (lost on the way down to it, and on to you)
		if (dist < 70.0) {
			// The caustics on what faces up, near.
			vec3 nview = normalize(cross(dFdx(vpos), dFdy(vpos)));
			if (dot(nview, vpos) > 0.0) {
				nview = -nview;
			}
			vec3 nw = mat3(INV_VIEW_MATRIX) * nview;
			float facing = clamp(dot(nw, normalize(p)) * 1.2 - 0.1, 0.0, 1.0);
			vec3 q = p + light_dir * (z_end / max(dot(light_dir, up), 0.3));   // (along the light, up to the surface)
			float c = uw_caustic(uw_plane(q), TIME, dist) * facing * exp(-z_end * 0.045) * (1.0 - smoothstep(25.0, 70.0, dist)) * uw_sun();
			k *= 1.0 + c * 1.6;
		}
	}
	ALBEDO = k;
}
