shader_type spatial;
// The light of a town's lamps on the ground, far from you (TownLamps): a soft
// warm disc under each lamp, added onto what's there - lit only by night (the
// town's lamp_lit), fading out near the camera where real lights take over.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 glow : source_color = vec3(1.0, 0.66, 0.36);
uniform float strength = 0.16;
uniform vec2 near_far = vec2(18.0, 32.0);   // m from the camera: none nearer than x, all of it past y
instance uniform float lamp_lit = 0.0;

void fragment() {
	float r = length(UV);
	float a = 1.0 - smoothstep(0.0, 1.0, r);
	a *= a;
	float d = length(VERTEX);
	a *= smoothstep(near_far.x, near_far.y, d) * lamp_lit * strength;
	ALBEDO = glow * a;
}
