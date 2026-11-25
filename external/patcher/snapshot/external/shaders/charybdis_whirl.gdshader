shader_type canvas_item;
// Charybdis (CharybdisBeast), the whole traced picture, alive: its vortex turns
// (the eye fastest, slowing to nothing by the teeth's tips - each pixel taken
// from further round), and the tentacles and spray at its rim writhe
// (taken from a little way round, in a wave running round the rim).

uniform vec2 tex_size;
uniform vec2 centre;              // texture px: the eye of the vortex
uniform float vortex = 125.0;     // px: inside this the vortex turns
uniform float reach = 580.0;      // px: the tentacles' tips
uniform float spin = 0.0;         // rad the eye has turned (set by the script)
uniform float writhe = 0.0;       // the rim's wave (set by the script)
uniform float churn = 0.0;        // 0..1: spinning harder (the whirlpool)

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 p = UV * tex_size - centre;
	float r = length(p);
	float a = atan(p.y, p.x);
	// The vortex: turned by spin at the eye, falling off to none at its edge.
	float v = clamp(1.0 - r / vortex, 0.0, 1.0);
	a -= spin * v * v * (1.0 + churn);
	// The rim: tentacles and spray writhing.
	float rim = smoothstep(reach * 0.55, reach, r);
	a += rim * (0.045 + 0.04 * churn) * sin(writhe + a * 7.0 + r * 0.01);
	vec2 q = centre + vec2(cos(a), sin(a)) * r;
	COLOR = texture(TEXTURE, q / tex_size) * tint;
	if (q.x < 0.0 || q.y < 0.0 || q.x > tex_size.x || q.y > tex_size.y) {
		COLOR.a = 0.0;
	}
}
