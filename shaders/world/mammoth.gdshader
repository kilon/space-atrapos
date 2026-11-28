// The mushroom mammoth's skin and fungus (CosmosMammoth): thick skin cracked
// into plates and folded at the joints, ringed along the trunk - bumped here
// from each vertex's rest place (CUSTOM0, so the detail rides with the bones) -
// mottled, with sparse coarse hair, mud and dust low on the legs, light
// through the thin ears; ivory tusks with growth lines, worn toenails, small
// dark glossy eyes; the fungus: a moist warted cap (c2), pale gills under it,
// a fibrous stalk. COLOR: r 0..0.2 fungus, 0.4 a nail, 0.6 a tusk, 0.8 an eye;
// g a fold's strength / the fungus's part (0 stalk, 0.5 gills, 1 cap) / along
// a tusk / an eye's depth; b thin and pink; a hair. A flash when hit.
shader_type spatial;
render_mode diffuse_burley, cull_back;

uniform vec4 c1 : source_color = vec4(0.45, 0.4, 0.38, 1.0);
uniform vec4 c2 : source_color = vec4(0.75, 0.2, 0.15, 1.0);
uniform float flash = 0.0;
uniform sampler3D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 rest;

void vertex() {
	rest = CUSTOM0.xyz;
}

float nz(vec3 p) {
	return texture(noise_tex, p).r;
}

// A crack network: thin lines where the noise crosses its middle.
float cracks(vec3 p, float sharp) {
	float n = nz(p);
	return pow(1.0 - abs(n * 2.0 - 1.0), sharp);
}

void fragment() {
	vec3 p = rest;
	float kind = COLOR.r;
	float fung = kind < 0.3 ? clamp(kind / 0.2, 0.0, 1.0) : 0.0;
	float g = COLOR.g;
	// How fine a detail still reads here (fading what would shimmer far off).
	float px = length(fwidth(p));
	float fine = 1.0 - smoothstep(0.004, 0.012, px);
	float mid = 1.0 - smoothstep(0.012, 0.04, px);
	float n_big = nz(p * 1.7 + vec3(0.3));
	float n_mid = nz(p * 5.3 + vec3(0.11, 0.7, 0.2));
	// --- The skin ---
	float plates = cracks(p * 6.0, 7.0) * mid;
	float fine_cr = cracks(p * 17.0 + vec3(0.5), 5.0) * fine;
	float fold = sin(UV.y * 95.0 + n_mid * 5.0 + UV.x * 1.5) * 0.5 + 0.5;
	fold = pow(fold, 3.0) * g * mid;
	float hairs = smoothstep(0.68 - COLOR.a * 0.1, 0.78 - COLOR.a * 0.08, nz(vec3(p.x * 34.0, p.y * 4.0, p.z * 34.0))) * mid * (0.15 + COLOR.a * 0.85);
	float h = -plates * 0.8 - fine_cr * 0.4 - fold * 0.9;
	vec3 skin = c1.rgb * (0.72 + 0.45 * n_big) * (0.92 + 0.16 * n_mid);
	skin *= 1.0 - plates * 0.22 - fine_cr * 0.1 - fold * 0.22;
	skin = mix(skin, c1.rgb * vec3(1.18, 0.86, 0.8) * 0.95, COLOR.b * 0.55);          // (pink: the ears' insides, the trunk's tip, the lip)
	skin = mix(skin, c1.rgb * vec3(0.42, 0.33, 0.26) + vec3(0.04, 0.025, 0.012), hairs * 0.8);   // (coarse brown hairs)
	float low = smoothstep(0.62, 0.08, p.y + (n_mid - 0.5) * 0.3);                  // (mud up the legs, caked at the feet)
	float dust = smoothstep(1.35, 1.6, p.y + (n_big - 0.5) * 0.3) * 0.22 * (1.0 - fung);           // (dust thrown over its back)
	skin = mix(skin, vec3(0.6, 0.54, 0.45) * (0.85 + 0.3 * n_mid), dust);
	skin = mix(skin, vec3(0.26, 0.2, 0.14) * (0.8 + 0.4 * n_mid), low * 0.85);
	float rough = mix(0.84, 0.95, max(low, plates)) - COLOR.b * 0.3;
	float spec = 0.32;
	vec3 albedo = skin;
	// --- The fungus ---
	if (fung > 0.0) {
		vec3 cream = vec3(0.9, 0.86, 0.76);
		vec3 f;
		float fh;
		float fr;
		if (g > 0.75) {   // (the cap: moist, warted, darker at its crown)
			float warts = smoothstep(0.64, 0.7, nz(p * 8.0 + vec3(7.1)));
			float scales = nz(vec3(p.x * 30.0, p.y * 30.0, p.z * 30.0)) * fine;
			f = c2.rgb * (0.78 + 0.4 * n_mid) * mix(0.75, 1.1, smoothstep(0.0, 0.5, UV.y));
			f = mix(f, cream * (0.85 + 0.2 * n_mid), warts);
			f *= 0.94 + scales * 0.12;
			fh = warts * 0.7 + scales * 0.2;
			fr = mix(0.38, 0.7, warts);
		} else if (g > 0.25) {   // (the gills: thin pale plates radiating to the rim)
			float gill = abs(sin(UV.x * 3.14159 * 112.0));
			f = mix(c2.rgb * 0.5 + cream * 0.35, cream * 0.95, gill) * (0.85 + 0.2 * n_mid);
			fh = gill * mid;
			fr = 0.8;
		} else {   // (the stalk: fibrous, stained toward its root)
			float fib = nz(vec3(p.x * 40.0, p.y * 3.0, p.z * 40.0));
			f = vec3(0.68, 0.61, 0.5) * (0.8 + 0.25 * fib) * mix(vec3(0.62, 0.52, 0.4), vec3(1.0), smoothstep(1.42, 1.7, p.y));
			f = mix(f, c2.rgb * 0.7 + vec3(0.2, 0.15, 0.1), 0.12);
			fh = fib * 0.4 * fine;
			fr = 0.72;
		}
		albedo = mix(skin, f, fung);
		h = mix(h, fh, fung);
		rough = mix(rough, fr, fung);
		spec = mix(spec, 0.42, fung);
	}
	// --- A toenail, a tusk, an eye ---
	if (kind > 0.3 && kind < 0.5) {
		albedo = vec3(0.6, 0.56, 0.48) * (0.75 + 0.35 * n_mid);
		albedo = mix(albedo, vec3(0.26, 0.2, 0.14), low * 0.6);
		h = -fine_cr * 0.3;
		rough = 0.6;
	} else if (kind > 0.5 && kind < 0.7) {
		float lines = sin(UV.y * 140.0 + n_mid * 3.0) * 0.5 + 0.5;
		albedo = vec3(0.7, 0.62, 0.47) * (0.88 + 0.16 * n_mid) * (0.95 + lines * 0.07);
		albedo = mix(albedo, vec3(0.52, 0.4, 0.27), (1.0 - smoothstep(0.0, 0.35, g)) * 0.7);   // (stained at the root)
		albedo = mix(albedo, vec3(0.95, 0.92, 0.84), smoothstep(0.85, 1.0, g) * 0.5);          // (the worn tip, polished)
		h = lines * 0.25 * fine;
		rough = mix(0.45, 0.25, g);
		spec = 0.5;
	} else if (kind > 0.7) {
		float k = g;
		albedo = mix(vec3(0.02, 0.015, 0.01), vec3(0.32, 0.17, 0.06), smoothstep(0.5, 0.8, k) * (1.0 - smoothstep(0.85, 1.0, k)));
		h = 0.0;
		rough = 0.06;
		spec = 0.7;
	}
	// The bump: the height's screen-space slope tilts the normal.
	float bump = 0.035;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(h) * bump;
	float dhy = dFdy(h) * bump;
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = spec;
	BACKLIGHT = (vec3(0.55, 0.22, 0.15) * COLOR.b * 0.5 + c2.rgb * fung * 0.18) * (kind < 0.3 ? 1.0 : 0.0);
	EMISSION = vec3(1.0, 0.25, 0.15) * flash;
}
