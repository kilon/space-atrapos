shader_type canvas_item;
// Skylla's upper body (SeaWitch): the traced art, her hair drifting as if in
// water - nothing moves below `still_y` (the crown, the face, the body), and
// the curls sway more the higher they are, in slow overlapping waves.

uniform vec2 tex_size;
uniform float still_y = 250.0;    // texture px: no sway from here down
uniform float top_y = 40.0;       // texture px: full sway from here up
uniform float sway = 9.0;         // px at the top
uniform float time_offset = 0.0;

varying vec4 tint;   // (the vertex colour: modulate, hit flashes)

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 p = UV * tex_size;
	float t = TIME + time_offset;
	float k = smoothstep(still_y, top_y, p.y);
	vec2 off = vec2(sin(t * 1.1 + p.y * 0.021 + p.x * 0.008) + 0.5 * sin(t * 1.7 + p.x * 0.019),
		0.5 * sin(t * 0.9 + p.x * 0.015)) * sway * k;
	vec2 uv = (p - off) / tex_size;
	COLOR = texture(TEXTURE, uv) * tint;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		COLOR.a = 0.0;
	}
}
