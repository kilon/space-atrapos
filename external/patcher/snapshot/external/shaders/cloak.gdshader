shader_type canvas_item;
// The cloak (Ship.cloak): the ship's shape becomes a lens - what's behind it
// seen through, bent by a slowly crawling ripple - with a faint shimmering
// rim where its edges catch the light. `amount` 0 -> 1 as it cloaks: a wave
// of distortion and sparkle sweeps across the hull, the paint fading out
// behind it (and back the other way when it ends).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float bend = 0.01;         // how far the background is shifted (screen UV)
uniform vec4 rim_color : source_color = vec4(0.75, 0.9, 1.0, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float a = tex.a;
	// The hull's edges: where the alpha changes (sampled round the pixel).
	vec2 px = TEXTURE_PIXEL_SIZE * 2.0;
	float around = texture(TEXTURE, UV + vec2(px.x, 0.0)).a + texture(TEXTURE, UV - vec2(px.x, 0.0)).a
		+ texture(TEXTURE, UV + vec2(0.0, px.y)).a + texture(TEXTURE, UV - vec2(0.0, px.y)).a;
	float edge = clamp(a * 4.0 - around, 0.0, 1.0);
	// A ripple crawling over the hull: the background bent through it.
	float n1 = noise(UV * 5.0 + vec2(TIME * 0.6, -TIME * 0.4));
	float n2 = noise(UV * 5.0 + vec2(-TIME * 0.5, TIME * 0.7) + 7.3);
	vec2 off = (vec2(n1, n2) - 0.5) * bend;
	// A lens: bent outward along the hull's outline, most near its edges (a
	// smooth gradient of its blurred alpha, so it reads as a shape).
	vec2 px4 = TEXTURE_PIXEL_SIZE * 6.0;
	vec2 grad = vec2(texture(TEXTURE, UV + vec2(px4.x, 0.0)).a - texture(TEXTURE, UV - vec2(px4.x, 0.0)).a,
		texture(TEXTURE, UV + vec2(0.0, px4.y)).a - texture(TEXTURE, UV - vec2(0.0, px4.y)).a);
	off -= grad * bend * 1.5;
	vec3 behind = textureLod(screen_tex, SCREEN_UV + off * amount, 0.0).rgb;
	// The sweep while it cloaks / uncloaks: a band of sparkle moving up the hull.
	float sweep = smoothstep(amount - 0.15, amount, 1.0 - UV.y) * (1.0 - smoothstep(amount, amount + 0.15, 1.0 - UV.y))
		* clamp(amount * (1.0 - amount) * 8.0, 0.0, 1.0);   // (only while it's coming on / going off)
	float sparkle = step(0.82, hash(floor(UV * 60.0) + floor(TIME * 12.0))) * sweep;
	float cloaked = smoothstep(0.0, 1.0, clamp((amount * 1.3) - (1.0 - UV.y) * 0.3, 0.0, 1.0));
	vec3 col = mix(tex.rgb, behind * 1.04 + vec3(0.01, 0.02, 0.03), cloaked);
	// The rim: a faint shimmer that moves round the edges.
	float shimmer = 0.5 + 0.5 * sin(TIME * 6.0 + (UV.x + UV.y) * 24.0 + n1 * 6.0);
	col += rim_color.rgb * edge * (0.35 + 0.45 * shimmer) * cloaked;
	col += rim_color.rgb * (sweep * 0.5 + sparkle);
	COLOR = vec4(col, a * mix(1.0, 0.92, cloaked));
}
