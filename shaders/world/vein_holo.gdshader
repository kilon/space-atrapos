// A scanned vein's hologram (CosmosVeins): its ore body as a glowing glass tube with a
// wireframe over it, seen through the ground - its 3D shape at a glance. Unlit, a faint
// glass skin (its edges brighter) under a bright cage, through the ground; never over a character (the automaton, people:
// their shader marks the stencil - pbr_vc). Bands sweep
// up through it (the scanner's pulse); `k` fades it out at the scan's end. What the
// digger has carved out of it (`cuts`, as you dig) is gone from it.
// Vertex COLOR: the ore's colour, alpha what's left of the vein (a dug-out one dim).
// `wire` 1: the cage's lines (the line surface), 0: the skin.
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 1;

uniform float k = 1.0;
uniform float wire = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 cuts[128];   // the digger's carves near you (CosmosPlanet._send_cuts): planet-local middle, radius
uniform int cut_n = 0;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	d = d * 2.0 - 1.0;   // (the web's renderer: OpenGL's depth range)
#endif
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene = -v.z / v.w;   // (how far what's drawn there is)
	float me = -VERTEX.z;
	bool behind = scene < me - 0.05;   // (under the ground: a little dimmer)
	float band = fract(length(lpos) * 0.35 - TIME * 0.6);
	float pulse = smoothstep(0.0, 0.08, band) * (1.0 - smoothstep(0.08, 0.3, band));
	float left = mix(0.45, 1.0, COLOR.a);
	vec3 c = mix(COLOR.rgb, vec3(1.0, 0.5, 0.12), 0.55);   // (its ore's colour, toward the HUD's orange: a hologram, even of a pale ore)
	c *= 1.0 / max(max(c.r, max(c.g, c.b)), 0.05);   // (at full brightness)
	for (int i = 0; i < cut_n; i++) {   // (inside a carve: dug out - gone from it, as you dig)
		if (length(lpos - cuts[i].xyz) < cuts[i].w * 0.85) {
			discard;
		}
	}
	if (wire > 0.5) {
		ALBEDO = mix(c, vec3(1.0), pulse * 0.6);
		ALPHA = k * left * (behind ? 0.75 : 0.95);
	} else {
		float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
		ALBEDO = c;
		ALPHA = k * left * (0.025 + rim * 0.16 + pulse * 0.12) * (behind ? 0.85 : 1.0);
	}
}
