// Recolours a raster character (a RigPuppet's sprite parts) by colour
// families: each slot finds one family in the art by hue (reds, oranges,
// yellows, blues) or by low saturation (pale cloth) and moves it to a target
// colour, keeping the painted shading (each pixel's brightness relative to
// the family's). Global hue / saturation / brightness / contrast and a tint
// go on top. Parameters come from NpcLook (scripts/npc_look.gd).
shader_type canvas_item;

uniform vec4 cloth_color : source_color = vec4(0.8, 0.15, 0.1, 1.0);
uniform float cloth_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 skin_color : source_color = vec4(0.75, 0.42, 0.18, 1.0);
uniform float skin_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 trim_color : source_color = vec4(0.95, 0.75, 0.3, 1.0);
uniform float trim_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tech_color : source_color = vec4(0.2, 0.55, 1.0, 1.0);
uniform float tech_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 pale_color : source_color = vec4(0.95, 0.92, 0.85, 1.0);
uniform float pale_amount : hint_range(0.0, 1.0) = 0.0;
uniform float hue_shift = 0.0;
uniform float saturation = 1.0;
uniform float brightness = 1.0;
uniform float contrast = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform float slot_width = 1.0;   // widens / narrows every slot's hue range
// Per body region (a RigPuppet tags each part, see RigPuppet.part_group):
// index 1 head / helmet, 2 body armour, 3 kilt, 4 cape, 5 front cloth,
// 6 arms, 7 legs, 8 weapon. part_color replaces the region's cloth (reds and
// pale), part_metal its metal (yellows); part_adj = (amount, hue shift,
// brightness, saturation).
uniform bool tagged = false;
uniform vec4 part_color[9] : source_color;
uniform vec4 part_metal[9] : source_color;
uniform vec4 part_adj[9];

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

// The art's colour families: [hue centre, half width, mean saturation,
// mean value] (measured on the art: the defaults are the characters'; the
// buildings' tiles set their own). fam_pale.x < 0: the pale slot takes
// low-saturation pixels instead of a hue family.
uniform vec4 fam_cloth = vec4(0.0, 0.05, 0.78, 0.6);
uniform vec4 fam_skin = vec4(0.062, 0.022, 0.68, 0.72);
uniform vec4 fam_trim = vec4(0.125, 0.045, 0.64, 0.93);
uniform vec4 fam_tech = vec4(0.6, 0.075, 0.76, 0.8);
uniform vec4 fam_pale = vec4(-1.0, 0.0, 0.0, 0.88);
#define CLOTH fam_cloth
#define SKIN fam_skin
#define TRIM fam_trim
#define TECH fam_tech

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// How much a pixel belongs to a hue family (soft edges, circular hue).
float member(vec3 hsv, vec4 fam) {
	float dh = abs(fract(hsv.x - fam.x + 0.5) - 0.5);
	float w = fam.y * slot_width;
	return smoothstep(w * 1.35, w * 0.65, dh) * smoothstep(0.18, 0.3, hsv.y) * smoothstep(0.06, 0.14, hsv.z);
}

// Moves a pixel to the target colour, keeping its shading.
vec3 recolor(vec3 hsv, vec4 fam, vec3 target) {
	vec3 t = rgb2hsv(target);
	float s = clamp(hsv.y * t.y / max(fam.z, 0.05), 0.0, 1.0);
	float v = clamp(hsv.z * t.z / max(fam.w, 0.05), 0.0, 1.0);
	return hsv2rgb(vec3(t.x, s, v));
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	int group = 0;
	if (tagged) {
		group = clamp(int(floor(vcol.r * 16.0)), 0, 8);
		src.a *= vcol.a;
	} else {
		src *= vcol;
	}
	vec3 col = src.rgb;
	vec3 hsv = rgb2hsv(col);
	float m;
	m = member(hsv, CLOTH) * cloth_amount;
	col = mix(col, recolor(hsv, CLOTH, cloth_color.rgb), m);
	m = member(hsv, SKIN) * skin_amount;
	col = mix(col, recolor(hsv, SKIN, skin_color.rgb), m);
	m = member(hsv, TRIM) * trim_amount;
	col = mix(col, recolor(hsv, TRIM, trim_color.rgb), m);
	m = member(hsv, TECH) * tech_amount;
	col = mix(col, recolor(hsv, TECH, tech_color.rgb), m);
	// Pale cloth: low saturation, not dark - tinted, keeping its brightness.
	if (fam_pale.x < 0.0) {
		m = smoothstep(0.3, 0.16, hsv.y) * smoothstep(0.35, 0.55, hsv.z) * pale_amount;
		col = mix(col, pale_color.rgb * hsv.z / fam_pale.w, m);
	} else {
		m = member(hsv, fam_pale) * pale_amount;
		col = mix(col, recolor(hsv, fam_pale, pale_color.rgb), m);
	}
	// This body region's own theme.
	vec4 adj = part_adj[group];
	if (group > 0 && adj.x > 0.0) {
		vec3 h0 = rgb2hsv(src.rgb);
		float mc = max(member(h0, CLOTH), smoothstep(0.3, 0.16, h0.y) * smoothstep(0.35, 0.55, h0.z));
		col = mix(col, recolor(h0, CLOTH, part_color[group].rgb), mc * adj.x);
		float mm = member(h0, TRIM);
		col = mix(col, recolor(h0, TRIM, part_metal[group].rgb), mm * adj.x);
	}
	if (group > 0) {
		vec3 ph = rgb2hsv(clamp(col, 0.0, 1.0));
		ph.x = fract(ph.x + adj.y);
		ph.y = clamp(ph.y * (adj.w == 0.0 ? 1.0 : adj.w), 0.0, 1.0);
		ph.z = clamp(ph.z * (adj.z == 0.0 ? 1.0 : adj.z), 0.0, 1.0);
		col = hsv2rgb(ph);
	}
	// Global adjustments.
	vec3 g = rgb2hsv(clamp(col, 0.0, 1.0));
	g.x = fract(g.x + hue_shift);
	g.y = clamp(g.y * saturation, 0.0, 1.0);
	col = hsv2rgb(g) * brightness;
	col = (col - 0.5) * contrast + 0.5;
	col = mix(col, col * tint.rgb * 1.4, tint_amount);
	COLOR = vec4(clamp(col, 0.0, 1.0), src.a);
}
