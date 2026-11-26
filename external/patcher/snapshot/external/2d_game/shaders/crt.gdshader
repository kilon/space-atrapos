shader_type canvas_item;
// An old CRT over the whole window (CrtFilter; tuned in Settings > CRT
// Filter): the picture bulges on a curved tube with rounded corners,
// scanlines, an RGB phosphor mask, a little colour fringing, a darker rim,
// a faint flicker and a slow rolling band.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float curvature = 0.07;            // how much the tube bulges
uniform float scanline_px = 3.0;           // screen pixels per scanline
uniform float scanline_strength = 0.38;
uniform float mask_strength = 0.14;        // the RGB phosphor stripes
uniform float fringe_px = 1.2;             // colour fringing (px at the edges)
uniform float vignette = 0.32;
uniform float brightness = 1.2;            // makes up for the dark lines
uniform float flicker = 0.012;             // 60 Hz shimmer
uniform float roll = 0.04;                 // the slow bright band rolling down
uniform float corner = 0.035;              // how round the tube's corners are

vec2 warp(vec2 uv) {
	vec2 c = uv * 2.0 - 1.0;
	c *= 1.0 + curvature * vec2(c.y * c.y, c.x * c.x);
	return c * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = warp(SCREEN_UV);
	// Outside the tube: black, with softly rounded corners.
	vec2 e = abs(uv * 2.0 - 1.0);
	vec2 q = max(e - (1.0 - corner), 0.0);
	float tube = corner > 0.0 ? 1.0 - smoothstep(corner - 0.006, corner, length(q)) : 1.0;
	tube *= step(e.x, 1.0) * step(e.y, 1.0);

	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 dir = (uv - 0.5) * 2.0;
	vec2 off = dir * fringe_px * px;
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;

	// Scanlines: each line bright in its middle, dark between.
	float line_y = uv.y / px.y / scanline_px;
	float scan = 0.5 + 0.5 * cos(line_y * 6.2831853);
	col *= 1.0 - scanline_strength * (1.0 - scan);
	// The aperture grille: R, G, B stripes.
	float stripe = mod(floor(FRAGCOORD.x), 3.0);
	vec3 mask = vec3(stripe == 0.0 ? 1.0 : 1.0 - mask_strength,
			stripe == 1.0 ? 1.0 : 1.0 - mask_strength,
			stripe == 2.0 ? 1.0 : 1.0 - mask_strength);
	col *= mask;
	// A darker rim, a faint flicker and a slow rolling band.
	float v = 1.0 - vignette * dot(dir * 0.75, dir * 0.75);
	float flick = 1.0 + flicker * sin(TIME * 60.0) + roll * smoothstep(0.92, 1.0, sin(uv.y * 3.0 - TIME * 1.3));
	col *= v * flick * brightness;
	COLOR = vec4(col * tube, 1.0);
}
