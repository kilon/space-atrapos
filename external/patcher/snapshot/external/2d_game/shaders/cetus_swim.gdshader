shader_type canvas_item;
// Cetus' body (CetusBeast), the traced top view, swimming: each pixel is
// taken from a little way across the body - a wave travelling from the head
// to the tail, growing toward the tail, as a whale's or a fish's stroke. The
// head (head_x) holds still. CetusBeast.bend() is the same curve, for the
// tail fin and the fins that ride on it.

uniform vec2 tex_size;
uniform float head_x = 30.0;      // texture px of the snout
uniform float body_len = 1500.0;  // texture px from the snout to the tail
uniform float amp = 34.0;         // px of sideways sway at the tail
uniform float phase = 0.0;        // the stroke (set by the script)

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 p = UV * tex_size;
	float s = clamp((p.x - head_x) / body_len, 0.0, 1.0);
	float off = amp * pow(s, 1.6) * sin(s * 6.2831853 * 0.8 - phase);
	vec2 uv = vec2(p.x, p.y - off) / tex_size;
	COLOR = texture(TEXTURE, uv) * tint;
	if (uv.y < 0.0 || uv.y > 1.0) {
		COLOR.a = 0.0;
	}
}
