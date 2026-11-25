shader_type spatial;
// The 3D maps' reference plane (a system's ecliptic, the galactic plane): a
// polar grid - rings every ring_step, spokes - fading out at its edge. With a
// fog (a system's: FogOfWar's texture - its alpha the dark), what your sensors
// haven't swept is a dim haze, the grid there faint.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec2 fog_origin = vec2(-160.0);
uniform vec2 fog_size = vec2(320.0);
uniform float has_fog = 0.0;
uniform vec4 grid_col : source_color = vec4(1.0, 0.62, 0.22, 1.0);
uniform vec4 haze_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float ring_step = 10.0;
uniform float extent = 160.0;
uniform float spokes = 12.0;
uniform float strength = 1.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	float r = length(p);
	float aa = max(fwidth(r), 1e-4);
	float rq = abs(fract(r / ring_step + 0.5) - 0.5) * ring_step;
	float ring = 1.0 - smoothstep(0.0, aa * 1.5, rq);
	float sect = 6.2831853 / spokes;
	float ang = atan(p.y, p.x);
	float sq = abs(fract(ang / sect + 0.5) - 0.5) * sect * r;
	float spoke = (1.0 - smoothstep(0.0, aa * 1.2, sq)) * smoothstep(ring_step * 0.5, ring_step * 1.5, r);
	float fade = 1.0 - smoothstep(extent * 0.75, extent, r);
	float seen = 1.0;
	if (has_fog > 0.5) {
		vec2 uv = (p - fog_origin) / fog_size;
		float inside = step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
		seen = inside * (1.0 - clamp(texture(fog_tex, uv).a / 0.93, 0.0, 1.0));
	}
	float g = (ring * 0.32 + spoke * 0.14) * fade * mix(0.18, 1.0, seen) * strength;
	float haze = has_fog * (1.0 - seen) * 0.42 * fade;
	float a = clamp(g + haze, 0.0, 1.0);
	ALBEDO = mix(haze_col.rgb, grid_col.rgb, g / max(g + haze, 1e-4));
	ALPHA = a;
}
