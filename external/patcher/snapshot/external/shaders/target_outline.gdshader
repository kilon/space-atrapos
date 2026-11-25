// Lock-on outline: a glowing outline that follows the sprite's own shape,
// with a soft halo, a pulse and bright dashes running round it. Drawn by a
// copy of the sprite behind the real one (see TargetOutline); the quad is
// enlarged in vertex() so the glow has room outside the texture.
shader_type canvas_item;

uniform vec4 color : source_color = vec4(1.0, 0.12, 0.08, 1.0);
uniform float width = 3.0;     // outline width, texture px
uniform float pad = 18.0;      // room for the halo, texture px

void vertex() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 dir = UV * 2.0 - 1.0;          // -1 / +1 at the corners
	VERTEX += dir * pad;
	UV = (UV * size + dir * pad) / size;
}

// 1 inside the texture, 0 outside (sampling outside clamps to the edge).
float inb(vec2 uv) {
	return step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float self_a = texture(TEXTURE, UV).a * inb(UV);
	// Ring of samples at the outline width, and wider rings for the halo.
	float near = 0.0;
	float halo = 0.0;
	for (int i = 0; i < 16; i++) {
		float ang = float(i) * 6.2831853 / 16.0;
		vec2 d = vec2(cos(ang), sin(ang));
		vec2 u1 = UV + d * px * width;
		vec2 u2 = UV + d * px * pad * 0.45;
		vec2 u3 = UV + d * px * pad * 0.9;
		near = max(near, texture(TEXTURE, u1).a * inb(u1));
		halo += texture(TEXTURE, u2).a * inb(u2);
		halo += texture(TEXTURE, u3).a * inb(u3);
	}
	halo /= 32.0;
	float line = clamp(near - self_a, 0.0, 1.0);
	// Pulse, plus dashes running round the shape (by angle from the centre).
	float pulse = 0.72 + 0.28 * sin(TIME * 6.0);
	vec2 c = UV - 0.5;
	float ang = atan(c.y, c.x);
	float dash = smoothstep(0.55, 0.9, sin(ang * 10.0 - TIME * 7.0));
	vec3 col = mix(color.rgb, vec3(1.0, 0.85, 0.75), dash * 0.65);
	float a = line * (0.75 + 0.25 * dash) + halo * (1.0 - self_a) * 1.15;
	COLOR = vec4(col, clamp(a * pulse, 0.0, 1.0) * color.a);
}
