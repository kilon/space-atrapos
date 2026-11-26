shader_type canvas_item;
render_mode blend_add;
// The trail a navigation beacon's scanning wave leaves (NavBeacon): a nebula
// of holographic gas where the wave's front has passed - noise, warped by
// noise, taken through thresholds into clumps and filaments, shimmering from
// cyan to violet with the beacon's colour, brightest just behind the front,
// fading out over foam_time. Drawn as a sector of quads round the beacon:
// UV.x across the wave's arc (0..1), UV.y out along its way (0..1; the
// front reaches y at y * wave_time); the vertex colour carries the wave:
// r its age / (wave_time + foam_time), g its seed, a its strength.

uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.45, 1.0, 0.7, 1.0);
uniform float wave_time = 1.5;
uniform float foam_time = 2.6;
uniform float slow = 1.0;        // (the whole animation this many times slower)
uniform float drift = 0.02;      // (how fast the gas drifts: per second)

// The wave's data, as the vertex colour came (in fragment(), COLOR is that
// times the texture's colour - the age would be scrambled by the noise).
varying vec4 wave;

void vertex() {
	wave = COLOR;
}

float n(vec2 p) {
	return texture(noise, p).r;
}

void fragment() {
	float age = wave.r * (wave_time + foam_time);
	float seed = wave.g;
	float strength = wave.a;
	float u = UV.x;
	float v = UV.y;
	float since = age - v * wave_time;              // since the front passed here
	if (since <= 0.0 || since > foam_time) {
		discard;
	}
	// The cone the wave swept: narrow by the beacon, opening as it went.
	float inside = abs(u - 0.5) * 2.0 / (0.6 + 0.4 * v);
	float edge = 1.0 - smoothstep(0.55, 1.0, inside);
	// Noise warped by noise, drifting outward, each wave its own patch.
	vec2 p = vec2((u - 0.5) * (0.4 + 0.8 * v), v * 1.0) + vec2(seed * 13.7, seed * 7.3);
	p.y -= TIME * drift + since * 0.03 / slow;
	vec2 warp = vec2(n(p * 0.5 + vec2(TIME * drift * 0.4, 0.0)), n(p * 0.5 + vec2(0.37, 0.71))) - 0.5;
	float n1 = n(p + warp * 0.7);
	float n2 = n(p * 1.6 - warp * 0.8 + vec2(0.0, since * 0.08 / slow));
	// Billowing clouds (a soft threshold), a haze round them, and a few thin
	// filaments (the sharp ridges of the finer noise, only inside the clouds).
	float clouds = smoothstep(0.42, 0.88, n1 * 0.8 + n2 * 0.3);
	float haze = smoothstep(0.35, 0.7, n1) * 0.35;
	float ridge = 1.0 - abs(n2 * 2.0 - 1.0);
	float fil = pow(ridge, 5.0) * clouds * 0.3;
	float d = clouds * (0.7 + 0.3 * n2) + haze + fil;
	// Brightest just behind the front, then fading.
	float fresh = exp(-since * 3.0 / slow);
	float fade = pow(1.0 - since / foam_time, 1.4);  // (to nothing at foam_time: no sudden end)
	float grow = smoothstep(0.0, 0.2 * slow, since); // (it blooms out of the front)
	float far = 1.0 - smoothstep(0.7, 1.0, v);      // (thinning out toward the end of its way)
	// Holographic: shimmering from cyan to violet (and a touch of the beacon's colour).
	float hue = n1 * 3.0 + n2 * 1.5 + v * 1.2 + seed * 6.0 + TIME * 0.3 / slow;
	vec3 holo = mix(vec3(0.15, 0.85, 1.0), vec3(0.75, 0.25, 1.0), 0.5 + 0.5 * sin(hue));
	vec3 col = mix(holo, tint.rgb, 0.2) * (1.0 + fil * 1.5) + vec3(0.6, 0.9, 1.0) * fresh * 0.25;
	float a = d * edge * fade * grow * (0.35 + 0.45 * fresh) * strength * smoothstep(0.0, 0.08, v) * far;
	COLOR = vec4(col, clamp(a, 0.0, 1.0));
}
