// The dragonfly's body (CosmosDragonfly): metallic and iridescent - its
// species' two colours shifting with the angle it's seen at, a thin film's
// rainbow over them; the abdomen's ten segments with dark joints, pale
// dorsal spots and a darker belly (UV.y: segment + place in it), flexing
// (UV.x: how far along it); the thorax's pale stripes; the compound eyes'
// facets (UV2: hexagons, a dark pseudopupil where you look straight in) -
// COLOR: r eye, g dark chitin, b thorax. A flash when hit.
shader_type spatial;
render_mode cull_back;

uniform vec4 c1 : source_color = vec4(0.2, 0.45, 0.7, 1.0);
uniform vec4 c2 : source_color = vec4(0.6, 0.85, 0.9, 1.0);
uniform float flash = 0.0;
uniform float flex = 0.0;      // (the abdomen bent: + up, - down)
uniform float sway = 0.0;      // (... and to the side)
uniform sampler3D noise_tex : filter_linear, repeat_enable;

varying vec3 v_obj;
varying vec3 v_on;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// A hexagonal grid: (distance to the cell's edge 0..0.5, the cell's random value).
vec2 hex(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	vec4 r = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, hc.xy) : vec4(h.zw, hc.zw + 0.5);
	vec2 q = abs(r.xy);
	float e = max(dot(q, s * 0.5), q.x);
	return vec2(0.5 - e, hash2(r.zw));
}

void vertex() {
	float t = UV.x;
	if (UV.y >= 0.0 && t > 0.0) {
		float b = t * t;
		VERTEX.y += flex * b * 0.07;
		VERTEX.x += sway * b * 0.05;
		NORMAL.z -= (flex * t * 0.14) * NORMAL.y;   // (roughly: the bend tilts the rings)
		NORMAL = normalize(NORMAL);
	}
	v_obj = VERTEX;
	v_on = NORMAL;
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float g = 1.0 - ndv;
	float n = texture(noise_tex, v_obj * 4.0).r;
	float eye = COLOR.r;
	float dark = COLOR.g;
	float thorax = COLOR.b;
	// The iridescent ground: c1 face-on, toward c2 at a slant, a thin film's hues over it.
	vec3 film = 0.5 + 0.5 * cos(6.2832 * (vec3(0.0, 0.33, 0.67) + g * 0.85 + n * 0.25 + v_obj.z * 0.6));
	vec3 base = mix(c1.rgb, c2.rgb, smoothstep(0.15, 0.95, g) * 0.65);
	base = mix(base, base * film * 1.7, 0.32 + 0.25 * g);
	float metal = 0.75;
	float rough = 0.26 + n * 0.08;
	// The abdomen: its segments' joints dark, pale spots on top (S2-S8), the belly darker.
	float seg = UV.y;
	if (seg >= 0.0 && eye < 0.5) {
		float f = fract(seg);
		float joint = smoothstep(0.0, 0.07, f) * (1.0 - smoothstep(0.93, 1.0, f));
		float dorsal = smoothstep(0.35, 0.85, v_on.y);
		float spot = dorsal * step(1.5, seg) * step(seg, 8.0) * (1.0 - smoothstep(0.12, 0.2, abs(f - 0.3))) * smoothstep(0.35, 0.0, abs(v_on.x) - 0.15);
		base = mix(base, c2.rgb * 1.15, spot * 0.75);
		base *= mix(1.0, 0.4, smoothstep(-0.05, -0.75, v_on.y));
		base *= mix(0.18, 1.0, joint);
		rough = mix(0.5, rough, joint);
	}
	// The thorax: two pale stripes up each side.
	float sd = abs(fract((v_obj.z + v_obj.y * 0.6) * 9.0) - 0.5);
	float stripe = (1.0 - smoothstep(0.06, 0.1, sd)) * smoothstep(0.2, 0.6, abs(v_on.x));
	base = mix(base, c2.rgb * 1.1, stripe * thorax * 0.8);
	// Dark chitin: the legs, the mouthparts, the claspers.
	base = mix(base, vec3(0.025, 0.025, 0.03) + film * 0.03, dark);
	metal = mix(metal, 0.35, dark);
	rough = mix(rough, 0.42, dark);
	// The compound eyes: thousands of facets, a dark pseudopupil looking back at you.
	if (eye > 0.5) {
		vec2 h = hex(UV2);
		float aa = fwidth(UV2.x) + fwidth(UV2.y);
		float edge = smoothstep(0.0, 0.06 + aa, h.x);
		float fade = clamp(1.0 - aa * 1.5, 0.0, 1.0);   // (facets under a pixel: the eye just glossy)
		vec3 ec = mix(c2.rgb, c1.rgb, 0.35 + 0.3 * smoothstep(0.0, -0.6, v_on.y)) * (0.75 + 0.35 * h.y * fade);
		ec = mix(ec, ec * film * 1.6, 0.25);
		ec *= mix(1.0, mix(0.35, 1.0, edge), fade);
		ec *= mix(1.0, 0.35, smoothstep(0.965, 0.995, ndv));
		float seam = (1.0 - smoothstep(0.003, 0.009, abs(v_obj.x))) * smoothstep(0.2, 0.6, v_on.y);   // (where the two eyes meet)
		ec = mix(ec, c1.rgb * 0.25, seam);
		base = ec;
		metal = 0.15;
		rough = mix(0.32, 0.08, edge * fade);
	}
	ALBEDO = base;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = 0.6;
	EMISSION = vec3(1.0, 0.25, 0.15) * flash;
}
