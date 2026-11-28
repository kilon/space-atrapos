// The sea's drifting specks (CosmosUnderwater): a box of tiny soft motes
// round the camera, each anchored in the world (it drifts with the water,
// not with you) and wrapped round the box as you swim - one draw. Drawn over
// the underwater pass (render priority), faded out near and far.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

uniform float box = 14.0;
uniform vec3 drift = vec3(0.035, 0.0, 0.025);    // world m/s (the current: carried along, not falling - no snowfall)
uniform vec4 tint : source_color = vec4(0.55, 0.72, 0.68, 0.16);   // (faint motes in the water's own colour)

varying vec2 v_uv;
varying float v_fade;

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;   // (rgb: its place in the box, a: its size)
	vec3 wp = cd.rgb * box + drift * TIME + sin(TIME * vec3(0.31, 0.27, 0.23) + cd.rgb * 40.0) * 0.18;   // (each its own slow wander)
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	wp = cam + mod(wp - cam, vec3(box)) - vec3(box * 0.5);
	vec3 vp = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	vp.xy += VERTEX.xy * (0.006 + 0.011 * cd.a);
	float d = length(vp);
	v_fade = (1.0 - smoothstep(box * 0.28, box * 0.5, d)) * smoothstep(0.25, 0.9, d);
	v_uv = VERTEX.xy * 2.0;
	POSITION = PROJECTION_MATRIX * vec4(vp, 1.0);
}

void fragment() {
	float r = dot(v_uv, v_uv);
	if (r > 1.0) {
		discard;
	}
	ALBEDO = tint.rgb;
	ALPHA = (1.0 - r) * v_fade * tint.a;
}
