// Energy shield bubble round a ship (on a ColorRect; the rect's shape becomes
// the oval - a square one makes the creatures' spheres). `glow` lights the whole shield; each hit adds a
// bright flare centred on its direction that spreads along the rim.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec4 color : source_color = vec4(0.3, 0.75, 1.0, 1.0);
uniform vec4 hit_color : source_color = vec4(0.75, 0.95, 1.0, 1.0);
uniform float glow = 0.0;
/// Hit directions in the rect's normalised (-1..1) space, and their strength.
uniform vec2 hit_dirs[4];
uniform float hit_power[4];

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float edge = smoothstep(1.0, 0.92, d);           // soft outer edge
	float shell = pow(clamp(d, 0.0, 1.0), 3.0) * edge; // brighter toward the rim
	vec2 n = d > 0.001 ? p / d : vec2(0.0, -1.0);

	// Whole-shield glow with a gentle moving shimmer.
	float shimmer = 0.8 + 0.2 * sin(d * 26.0 - TIME * 5.0 + atan(p.y, p.x) * 4.0);
	vec3 col = color.rgb * (shell * 0.9 + 0.08 * edge) * glow * shimmer;
	// A sphere's light: a soft highlight up and to the left, a rim of light
	// opposite it - so a round shield reads as a ball of energy.
	float spec = exp(-length(p - vec2(-0.38, -0.42)) * 4.5) * edge;
	float rim = pow(max(dot(n, vec2(0.6, 0.7)), 0.0), 3.0) * shell;
	col += color.rgb * (spec * 0.35 + rim * 0.4) * glow;

	for (int i = 0; i < 4; i++) {
		float power = hit_power[i];
		if (power <= 0.0) {
			continue;
		}
		vec2 dir = normalize(hit_dirs[i]);
		float facing = max(dot(n, dir), 0.0);
		// Wide flare across the hit side of the shell...
		float flare = pow(facing, 6.0) * (0.25 + shell) * edge;
		// ...and a hot spot right where the bullet struck.
		float core = exp(-length(p - dir * 0.93) * 7.0) * edge;
		col += hit_color.rgb * power * (flare * 1.4 + core * 2.2);
	}

	COLOR = vec4(col, 1.0);
}
