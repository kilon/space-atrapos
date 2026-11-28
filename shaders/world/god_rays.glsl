#[compute]
#version 450
// The sun's rays (CosmosGodRays): shafts of light through the gaps in the
// clouds and the trees. Three passes over the frame after its transparent
// things (the clouds, the air) are drawn:
//   0 the mask (half size): the open sky near the sun - not behind anything
//     drawn (the depth's far), brighter as it's bright (the clouds' gaps, the
//     sun's glow) and nearer the sun on screen;
//   1 the rays (half size): the mask smeared along the lines to the sun,
//     fading out along them;
//   2 added to the frame (full size), tinted by the light.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D depth_tex;
layout(rgba16f, set = 0, binding = 1) uniform image2D color_img;
layout(r16f, set = 0, binding = 2) uniform image2D mask_img;
layout(r16f, set = 0, binding = 3) uniform image2D rays_img;

layout(push_constant, std430) uniform Params {
	vec2 size;        // the frame's
	vec2 half_size;   // the masks'
	vec2 sun;         // the sun on screen (0..1, may be off it)
	float strength;
	float mode;
	vec4 tint;        // the light's colour; w: how wide its reach on screen
} p;

void main() {
	ivec2 gid = ivec2(gl_GlobalInvocationID.xy);
	if (p.mode < 0.5) {
		if (gid.x >= int(p.half_size.x) || gid.y >= int(p.half_size.y)) return;
		ivec2 px = gid * 2;
		vec2 uv = (vec2(px) + 1.0) / p.size;
		float depth = texture(depth_tex, uv).r;
		float sky = depth <= 0.000001 ? 1.0 : 0.0;   // (reverse z: nothing drawn there - the sky, the clouds over it)
		vec3 c = imageLoad(color_img, px).rgb;
		float lum = dot(c, vec3(0.3, 0.59, 0.11));
		vec2 dsun = (uv - p.sun) * vec2(p.size.x / p.size.y, 1.0);
		float near_sun = exp(-dot(dsun, dsun) / max(p.tint.w * p.tint.w, 1e-4));
		imageStore(mask_img, gid, vec4(sky * smoothstep(0.08, 0.9, lum) * near_sun));
	} else if (p.mode < 1.5) {
		if (gid.x >= int(p.half_size.x) || gid.y >= int(p.half_size.y)) return;
		vec2 uv = (vec2(gid) + 0.5) / p.half_size;
		const int N = 40;
		vec2 step_uv = (p.sun - uv) / float(N);
		float acc = 0.0;
		float w = 1.0;
		vec2 q = uv;
		for (int i = 0; i < N; i++) {
			q += step_uv;
			ivec2 qi = ivec2(clamp(q, vec2(0.0), vec2(0.9999)) * p.half_size);
			acc += imageLoad(mask_img, qi).r * w;
			w *= 0.955;
		}
		imageStore(rays_img, gid, vec4(acc / float(N) * p.strength));
	} else {
		if (gid.x >= int(p.size.x) || gid.y >= int(p.size.y)) return;
		vec4 c = imageLoad(color_img, gid);
		float r = imageLoad(rays_img, gid / 2).r;
		c.rgb += p.tint.rgb * r;
		imageStore(color_img, gid, c);
	}
}
