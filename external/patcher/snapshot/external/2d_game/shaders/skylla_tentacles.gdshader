shader_type canvas_item;
// Skylla's tentacles (SeaWitch), the traced art itself made to writhe: each
// pixel is taken from a little way along the tentacle it belongs to - more the
// farther it is from the hub, so the roots hold and the tips sway most - with
// a wave travelling out along every tentacle and a slow coil, each tentacle
// (by its angle round the hub) out of step with the next.

uniform vec2 tex_size;            // the texture's size in px
uniform vec2 hub;                 // the tentacles' hub, in texture px
uniform float sway = 26.0;        // px of sideways sway at the tips
uniform float reach = 520.0;      // px from the hub to the tips
uniform float speed = 1.0;
uniform float time_offset = 0.0;

varying vec4 tint;   // (the vertex colour: modulate, hit flashes)

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 p = UV * tex_size - hub;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float t = TIME * speed + time_offset;
	float k = smoothstep(50.0, reach, r);               // 0 at the roots, 1 at the tips
	vec2 radial = p / max(r, 1.0);
	vec2 tang = vec2(-radial.y, radial.x);
	float wave = sin(t * 1.5 - r * 0.016 + ang * 3.0) + 0.45 * sin(t * 0.9 - r * 0.009 + ang * 5.0);
	float coil = sin(t * 0.7 + ang * 2.0);
	vec2 off = tang * sway * k * k * wave + radial * sway * 0.35 * k * coil;
	vec2 uv = (p - off + hub) / tex_size;
	COLOR = texture(TEXTURE, uv) * tint;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		COLOR.a = 0.0;
	}
}
