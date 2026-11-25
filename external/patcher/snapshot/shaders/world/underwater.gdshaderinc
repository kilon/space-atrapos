// Under the sea (CosmosUnderwater): what its two full-screen passes share -
// the uniforms the script sets (on both), the caustics' and shafts' noise
// net, and each pixel's view ray against the depth buffer and the sea's
// surface (seen from inside its sphere). Depth only - no copy of the
// screen: the absorption is a multiply pass (underwater.gdshader), the
// water's own light an additive one (underwater_glow.gdshader).

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform vec3 eye_rel = vec3(0.0, 2990.0, 0.0);   // the camera from the planet's centre (world axes, m)
uniform vec3 up = vec3(0.0, 1.0, 0.0);           // at the camera
uniform float radius = 3000.0;                   // the sea's surface
uniform float eye_depth = 10.0;                  // m under it
uniform vec3 light_dir = vec3(0.0, 1.0, 0.0);    // towards the sun, under the water (refracted)
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);      // towards the sun, above it
uniform vec3 axis_u = vec3(1.0, 0.0, 0.0);       // the floor's plane, for the caustics' pattern
uniform vec3 axis_v = vec3(0.0, 0.0, 1.0);
uniform vec3 anchor = vec3(0.0, 2990.0, 0.0);    // (the pattern's origin, near the camera: small numbers)
uniform vec3 absorb = vec3(0.16, 0.045, 0.032);  // per m: sunlight lost on its way down
uniform vec3 extinct = vec3(0.13, 0.052, 0.042); // per m: along the view
uniform vec4 water : source_color = vec4(0.1, 0.42, 0.5, 1.0);   // the sea's own scattered colour
uniform vec4 sky : source_color = vec4(0.55, 0.75, 0.95, 1.0);   // the sky through the window
uniform float light = 1.0;                       // the sun's strength now (night: low)

// Where two drifting noise fields cross the same value, a thin bright line:
// a churning net, like the light the waves focus.
float uw_net(vec2 p, float t) {
	float a = texture(noise_tex, vec3(p, t * 0.05)).r;
	float b = texture(noise_tex, vec3(p + 0.31, 0.5 - t * 0.043)).r;
	float l = 1.0 - min(abs(a - b) * 5.0, 1.0);
	return l * l * l * l;
}

// The caustics: two scales of the net, the second turned (no tiling seen), near.
float uw_caustic(vec2 p, float t, float dist) {
	float c = uw_net(p * 0.075, t);
	if (dist < 28.0) {   // (the fine net only near: further it's lost in the murk)
		vec2 r = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8);
		c += uw_net(r * 0.17 + 0.4, t * 1.4) * 0.6 * (1.0 - smoothstep(18.0, 28.0, dist));
	}
	return c;
}

vec2 uw_plane(vec3 p) {
	return vec2(dot(p - anchor, axis_u), dot(p - anchor, axis_v));
}

// This pixel's ray (world), what it hits (view-space point, distance; 1e6:
// nothing) and where it leaves the sea (t_s along it).
void uw_ray(vec2 uv, mat4 inv_proj, mat4 inv_view, out vec3 rd, out vec3 vpos, out float dist, out float t_s) {
	float z = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	bool hit = z < 1.0;   // (the web's renderer: OpenGL's depth - far is 1, the range -1..1)
	z = z * 2.0 - 1.0;
#else
	bool hit = z > 0.0;   // (reversed depth: far is 0)
#endif
	vec4 nv = inv_proj * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	rd = normalize(mat3(inv_view) * normalize(nv.xyz / nv.w));
	dist = 1e6;
	vpos = vec3(0.0);
	if (hit) {
		vec4 vp = inv_proj * vec4(uv * 2.0 - 1.0, z, 1.0);
		vpos = vp.xyz / vp.w;
		dist = length(vpos);
	}
	float b = dot(eye_rel, rd);
	float c = -eye_depth * (2.0 * radius - eye_depth);
	t_s = -b + sqrt(max(b * b - c, 0.0));
}

// The sun's strength under the water now (its height over the horizon, the night).
float uw_sun() {
	return light * smoothstep(-0.05, 0.15, dot(sun_dir, up));
}
