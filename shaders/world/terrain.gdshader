// A planet's ground in the 3D game (CosmosPlanet's terrain patches): coloured
// by height, slope, latitude and a 3D noise (the planet's PlanetGen palette -
// the same colours as its 2D look); lit by its star from `sun_dir` (each
// planet has its own: the sun is a point, the scene's one light follows the
// ship), shadows from that light near the ship. Where the ground's been
// carved (digging), not drawn inside the carves: the voxels' mesh is there.
// The ore veins under the ground (CosmosVeins, `vein_*`): the scanner's ghost
// of them glows through the ground over where they lie (only the ground: it's
// the ground drawing it, so whatever stands on it hides it), and where the
// digger's cut into one (the voxels' ground, `voxel`) its walls are solid ore.
shader_type spatial;
render_mode cull_back, specular_disabled;

// Where a vertex is on its planet (v_local) and whether carves are near it (v_cut: not drawn inside
// them - CosmosVoxels draws the ground there). The carved ground's own chunks say so in UV.y (1).
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
// (The web's renderer: no instance uniforms - each instance takes 16 of its 4096 slots, 256 in all,
// and there are ~700 patches. The planet's inverse transform instead, set every frame - CosmosPlanet.)
uniform mat4 planet_inv;
#else
instance uniform vec4 patch_info;        // xyz the patch's centre, planet-local; w 1: carves near it
#endif
uniform vec4 cuts[128];                  // the carves nearest you: planet-local middle, radius (out to their roughest)
uniform int cut_n = 0;
varying float v_cut;
varying float v_vox;
const int VEINS = 16;
uniform int vein_n = 0;                  // the veins known round you (the nearest; 0 on other worlds)
uniform int ghost_n = 0;                 // the first of them the scanner's shown (their ghosts)
uniform vec4 vein_bound[VEINS];          // planet-local middle, reach (as far as its ghost glows across the ground)
uniform vec4 vein_col[VEINS];            // the mineral's colour (sRGB), what's left of it (0 .. 1)
uniform vec4 vein_look[VEINS];           // metallic, glow, crystal, -
uniform vec4 vein_span[VEINS];           // its points in vein_pts: x the first, y past its last (floats: int arrays aren't packed as the GPU reads them)
uniform vec4 vein_pts[384];              // its chains: planet-local points, radius (a radius < 0: a break between two chains)
uniform float ghost_k = 0.0;             // the ghost's strength (fading out at its end; 0: none - nothing done)
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float radius = 3000.0;
uniform float amp = 80.0;
uniform int sea = 0;                     // 0 none, 1 water, 2 ice, 3 lava
uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform vec4 land_low : source_color = vec4(0.35, 0.3, 0.22, 1.0);
uniform vec4 land_mid : source_color = vec4(0.5, 0.4, 0.3, 1.0);
uniform vec4 land_high : source_color = vec4(0.3, 0.28, 0.27, 1.0);
uniform vec4 land_peak : source_color = vec4(0.75, 0.73, 0.7, 1.0);
uniform float biome = 0.0;
uniform vec4 biome_color : source_color = vec4(0.7, 0.35, 0.15, 1.0);
uniform float ice_cover = 0.0;
uniform vec4 ice_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float lava = 0.0;
uniform vec4 lava_color : source_color = vec4(1.0, 0.3, 0.05, 1.0);
uniform vec4 lava_hot : source_color = vec4(1.0, 0.85, 0.35, 1.0);
uniform vec4 water_shallow : source_color = vec4(0.1, 0.5, 0.6, 1.0);
uniform vec4 water_deep : source_color = vec4(0.02, 0.1, 0.25, 1.0);

varying vec3 v_local;
varying float v_h;
varying vec4 v_ore;                      // (to light(): the ore's sheen - its tint, how much)

void vertex() {
	v_vox = UV.y;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	v_local = (planet_inv * (MODEL_MATRIX * vec4(VERTEX, 1.0))).xyz;
	v_cut = 0.0;
	if (v_vox < 0.5) {
		for (int i = 0; i < cut_n; i++) {   // (a carve near this vertex: its triangles look at the carves)
			if (length(v_local - cuts[i].xyz) < cuts[i].w + 8.0) {
				v_cut = 1.0;
			}
		}
	}
#else
	v_local = VERTEX + patch_info.xyz;
	v_cut = patch_info.w;
#endif
	v_h = UV.x;
}

float nz(vec3 p) {
	return texture(noise_tex, p).r;
}

// The vein ghost at a bit of ground (planet-local p, its up): the nearest
// revealed vein across the ground (perpendicular to up) - its body filled,
// its outline sharp, a faint halo, fainter the deeper it lies, a slow pulse
// running along it; the parts the digger's already been into (the carves
// near) grey. rgb the glow's colour (saturated), a how much.
vec4 vein_ghost(vec3 p, vec3 up) {
	float bh = 9.0;
	float bdep = 0.0;
	vec3 bq = vec3(0.0);
	int bi = 0;
	float br = 1.0;
	for (int i = 0; i < ghost_n; i++) {
		vec3 dc = p - vein_bound[i].xyz;
		dc -= up * dot(dc, up);   // (across the ground: how far its glow reaches, whatever the depth)
		if (dot(dc, dc) > vein_bound[i].w * vein_bound[i].w) continue;
		for (int j = int(vein_span[i].x); j < int(vein_span[i].y) - 1; j++) {
			if (vein_pts[j].w < 0.0 || vein_pts[j + 1].w < 0.0) continue;   // (a break between its chains)
			vec3 a = vein_pts[j].xyz;
			vec3 ab = vein_pts[j + 1].xyz - a;
			float r = max(vein_pts[j].w, vein_pts[j + 1].w);
			vec3 abt = ab - up * dot(ab, up);
			vec3 ap = p - a;
			vec3 apt = ap - up * dot(ap, up);
			float t = clamp(dot(apt, abt) / max(dot(abt, abt), 1e-4), 0.0, 1.0);
			vec3 q = a + ab * t;
			vec3 dq = p - q;
			float dep = dot(dq, up);
			float h = length(dq - up * dep);
			if (h / r < bh) {   // (the nearest: their union's outline)
				bh = h / r;
				bdep = dep;
				bq = q;
				bi = i;
				br = r;
			}
		}
	}
	if (bh >= 2.6) return vec4(0.0);
	float body = 1.0 - smoothstep(0.85, 1.0, bh);
	float rim = smoothstep(0.7, 0.92, bh) * (1.0 - smoothstep(0.98, 1.12, bh));
	float halo = (1.0 - smoothstep(1.0, 2.6, bh)) * 0.18;
	float streak = 0.75 + 0.5 * nz(bq / 2.2 + p / 5.0);
	float run = 0.5 + 0.5 * sin(TIME * 1.6 - dot(bq, vec3(0.37, 0.29, 0.41)));   // (a slow pulse along it)
	float a = body * (0.42 + 0.18 * run) * streak + rim * 0.75 + halo;
	a *= mix(1.0, 0.35, clamp((bdep - 2.5) / 8.5, 0.0, 1.0));   // (the deeper, the fainter)
	float mined = 0.0;
	for (int i = 0; i < cut_n; i++) {
		float reach = cuts[i].w + br * 0.6;
		mined = max(mined, 1.0 - smoothstep(reach * 0.8, reach, length(bq - cuts[i].xyz)));
	}
	vec3 c = pow(vein_col[bi].rgb, vec3(2.2));   // (LOOK's colours are sRGB)
	c = c / max(max(c.r, max(c.g, c.b)), 0.02);   // (its hue at full strength)
	float left = vein_col[bi].a;
	vec3 spent = vec3(0.55, 0.56, 0.6);
	return vec4(mix(c, spent, mined), a * mix(0.55 + 0.45 * left, 0.45, mined) * ghost_k);
}

// The ore where a dug wall's inside a vein (p planet-local): x the vein (-1
// none), y how much (its edge soft, its boundary ragged by the noise).
vec2 vein_ore(vec3 p) {
	float best = 0.0;
	int bi = -1;
	float wob = nz(p / 3.1) - 0.5;
	for (int i = 0; i < vein_n; i++) {
		vec3 dc = p - vein_bound[i].xyz;
		if (dot(dc, dc) > vein_bound[i].w * vein_bound[i].w) continue;
		for (int j = int(vein_span[i].x); j < int(vein_span[i].y) - 1; j++) {
			if (vein_pts[j].w < 0.0 || vein_pts[j + 1].w < 0.0) continue;   // (a break between its chains)
			vec3 a = vein_pts[j].xyz;
			vec3 ab = vein_pts[j + 1].xyz - a;
			float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
			float r = mix(vein_pts[j].w, vein_pts[j + 1].w, t) * (1.0 + wob * 0.5);   // (swelling, thinning to its tendrils' tips)
			float d = length(p - a - ab * t);
			float o = 1.0 - smoothstep(r - 0.12, r + 0.05, d);
			if (o > best) {
				best = o;
				bi = i;
			}
		}
	}
	return vec2(float(bi), best);
}

vec3 grad4(vec3 a, vec3 b, vec3 c, vec3 d, float t) {
	if (t < 0.33) return mix(a, b, t / 0.33);
	if (t < 0.7) return mix(b, c, (t - 0.33) / 0.37);
	return mix(c, d, (t - 0.7) / 0.3);
}

void fragment() {
	if (v_cut > 0.0) {   // (carves near)
		for (int i = 0; i < cut_n; i++) {
			vec3 dl = v_local - cuts[i].xyz;
			if (dot(dl, dl) < cuts[i].w * cuts[i].w) {
				discard;
			}
		}
	}
	vec3 up = normalize(v_local);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - clamp(dot(wn, up), 0.0, 1.0);
	float dist = length(VERTEX);
	// Noise at three scales: the planet's (biomes), a field's, underfoot
	// (faded out with distance: no shimmer).
	float n0 = nz(up * 2.3);
	float n1 = nz(v_local / 420.0);
	float n2 = nz(v_local / 23.0);
	float near = 1.0 - smoothstep(150.0, 900.0, dist);
	float hl;
	vec3 col;
	if (sea > 0) {
		// Sand on the shores, then the land's own colours up to the peaks.
		hl = clamp(v_h / (amp * 1.8) + (n0 - 0.5) * 0.22 + (n1 - 0.5) * 0.1, 0.0, 1.0);
		col = hl < 0.5 ? mix(land_mid.rgb, land_high.rgb, hl / 0.5) : mix(land_high.rgb, land_peak.rgb, smoothstep(0.5, 0.95, hl));
		float sand = 1.0 - smoothstep(amp * 0.015, amp * 0.05, v_h + (n2 - 0.5) * amp * 0.03 * near + (n1 - 0.5) * amp * 0.03);
		col = mix(col, land_low.rgb, sand);
	} else {
		hl = clamp((v_h + amp) / (amp * 3.0) + (n0 - 0.5) * 0.25 + (n1 - 0.5) * 0.12, 0.0, 1.0);
		col = grad4(land_low.rgb, land_mid.rgb, land_high.rgb, land_peak.rgb, hl);
	}
	if (biome > 0.0) {
		float bp = smoothstep(0.48, 0.6, nz(up * 1.4 + 3.7));
		col = mix(col, biome_color.rgb * (0.8 + 0.4 * n1), bp * biome * (1.0 - hl * 0.6));
	}
	// Bare rock on the steep slopes, the ground's grain close up.
	vec3 rock = mix(land_high.rgb, land_low.rgb, 0.4) * (0.7 + 0.4 * n1);
	col = mix(col, rock, smoothstep(0.25, 0.55, slope + (n2 - 0.5) * 0.15 * near));
	col *= 0.82 + 0.36 * mix(n1, n2, near);
	// Under the sea: its floor, darker with depth.
	if (sea == 1 && v_h < 0.0) {
		col = mix(col, water_deep.rgb * 0.6, clamp(-v_h / (amp * 0.5), 0.0, 0.8));
	}
	// Snow on the heights and the poles.
	if (ice_cover > 0.0 || sea == 2) {
		float cover = max(ice_cover, sea == 2 ? 0.35 : 0.0);
		float snow = smoothstep(0.0, 0.1, hl - (1.0 - cover) + (n1 - 0.5) * 0.3);
		float polar = smoothstep(0.0, 0.06, abs(up.y) - (1.0 - cover * 0.7) + (n0 - 0.5) * 0.25);
		float ice = max(snow * (1.0 - smoothstep(0.35, 0.6, slope)), polar);
		col = mix(col, ice_color.rgb * (0.85 + 0.2 * n2), ice);
	}
	vec3 emit = vec3(0.0);
	float rough = 0.95;
	v_ore = vec4(0.0);
	// Dug into a vein: its ore in the walls - the mineral's colour, banded
	// and veined, metal glinting or crystals catching the light.
	if (v_vox > 0.5 && vein_n > 0) {   // (the carved ground)
		vec2 ore = vein_ore(v_local);
		if (ore.x >= 0.0) {
			int i = int(ore.x);
			vec3 oc = pow(vein_col[i].rgb, vec3(2.2));   // (sRGB: to linear)
			vec4 lk = vein_look[i];
			float b1 = nz(v_local / 1.3 + vec3(0.0, 4.1, 0.0));
			float b2 = nz(v_local / 0.8 + vec3(2.3, 0.0, 1.1));
			float band = smoothstep(0.42, 0.6, b1);
			float seam = smoothstep(0.93, 0.98, 1.0 - abs(b2 * 2.0 - 1.0));   // (thin seams of the purest)
			vec3 host = mix(col, oc * 0.28, 0.55);
			vec3 o = mix(oc * 0.7, oc * 1.25, band) * (0.85 + 0.3 * b2);
			o = mix(o, host, (1.0 - band) * 0.35);
			o = mix(o, oc * 1.6 + 0.04, seam * 0.5);
			float glint = 0.0;
			if (lk.z > 0.5) {
				glint = smoothstep(0.78, 0.86, nz(v_local / 0.21 + vec3(7.0)));   // (facets)
			}
			col = mix(col, o, ore.y);
			rough = mix(rough, mix(0.42, 0.18, lk.z) - lk.x * 0.1, ore.y);
			vec3 tint = lk.z > 0.5 ? vec3(0.1) : mix(vec3(0.04), oc * 1.4, lk.x);   // (metal's highlight its own colour; a crystal's white, in glints)
			v_ore = vec4(tint, ore.y * (1.0 + glint * 8.0));
			emit += (oc * lk.y * 1.5 + o * 0.22 + oc * glint * 0.15) * ore.y;   // (its own glow if it has one; the sky's light off it down in the pit's shade)
		}
	}
	if (ghost_k > 0.0 && ghost_n > 0 && v_vox < 0.5) {   // (the scanner's shown the veins here: glowing through the ground - not in a pit's walls: the ore itself there)
		vec4 g = vein_ghost(v_local, up);
		col = mix(col, g.rgb * 0.3, min(g.a, 1.0) * 0.8);
		emit += g.rgb * g.a * 0.5;
	}
	if (lava > 0.0) {
		float lr = 1.0 - abs(nz(up * 3.1 + 1.3) * 2.0 - 1.0);
		float crack = smoothstep(0.9, 0.98, lr) * (1.0 - smoothstep(0.0, 0.4, hl));
		float m = clamp(crack * lava, 0.0, 1.0);
		col = mix(col, lava_color.rgb * 0.3, m);
		emit = mix(lava_color.rgb, lava_hot.rgb, m * m) * m * 2.0;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emit;
}

void light() {
	vec3 L = normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz);
	float d = clamp(dot(NORMAL, L), 0.0, 1.0);
	DIFFUSE_LIGHT += d * ATTENUATION * LIGHT_COLOR / PI;
	if (v_ore.a > 0.0) {   // (the ore's sheen: a highlight of the sun, tinted)
		vec3 H = normalize(L + VIEW);
		float sh = 2.0 / max(ROUGHNESS * ROUGHNESS, 0.01);
		float s = pow(clamp(dot(NORMAL, H), 0.0, 1.0), sh) * (sh + 2.0) / 8.0;
		SPECULAR_LIGHT += v_ore.rgb * v_ore.a * s * d * ATTENUATION * LIGHT_COLOR / PI;
	}
}
