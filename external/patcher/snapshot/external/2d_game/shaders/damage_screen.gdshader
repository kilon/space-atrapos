shader_type canvas_item;
// A failing monitor over the whole screen (DamageScreen): static, rolling tear
// lines, a flicker, darkened edges - `k` 0 (nothing) .. 1 (near death; still
// readable: kept faint on purpose).
uniform float k : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	// Static: coarse grains (2 px), changing 30 times a second.
	vec2 cell = floor(FRAGCOORD.xy / 2.0);
	float n = hash(cell + floor(t * 30.0) * 17.0);
	// Rolling bands of worse static.
	float band = smoothstep(0.92, 1.0, sin(uv.y * 9.0 - t * 2.3) * 0.5 + 0.5);
	// A torn line now and then.
	float row = floor(uv.y * 140.0);
	float tear = step(0.985, hash(vec2(row, floor(t * 12.0)))) * k;
	// The flicker: the whole screen dims for a moment.
	float flick = step(0.93, hash(vec2(floor(t * 14.0), 3.1))) * 0.25 * k;
	// Dark round the edges.
	vec2 d = uv - 0.5;
	float vig = smoothstep(0.35, 0.75, length(d * vec2(1.0, 0.8)));
	float a = k * (0.16 + band * 0.22) * n + tear * 0.35 + flick + vig * k * 0.45;
	vec3 c = mix(vec3(n), vec3(0.0), 0.35 + vig * 0.6);
	c = mix(c, vec3(0.9, 0.95, 1.0), tear);
	COLOR = vec4(c, clamp(a, 0.0, 0.7));
}
