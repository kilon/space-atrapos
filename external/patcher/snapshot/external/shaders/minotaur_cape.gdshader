shader_type canvas_item;
// The Minotaur's body (MinotaurBoss), the traced art, his red cape rippling:
// where the cape mask is set, each pixel is taken from a little way along a
// wave travelling out through the cloth; the rest of him holds still.

uniform sampler2D cape_mask;      // the cape, softened (same size as the texture)
uniform vec2 tex_size;
uniform float sway = 16.0;        // px at full mask
uniform float time_offset = 0.0;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 p = UV * tex_size;
	float t = TIME + time_offset;
	float m = texture(cape_mask, UV).r;
	vec2 off = vec2(sin(t * 2.1 + p.y * 0.022 + p.x * 0.006) + 0.4 * sin(t * 3.3 + p.x * 0.03),
		cos(t * 1.7 + p.x * 0.018) * 0.8) * sway * m;
	vec2 uv = (p - off) / tex_size;
	COLOR = texture(TEXTURE, uv) * tint;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		COLOR.a = 0.0;
	}
}
