// A sea's waves (water_surface.gdshader; CosmosWaters.wave_height works out the same in
// script - a swimmer rides them): a few long directional waves, each a plane wave through
// the planet-local space along its own way (round the wind's), their way along the ground
// wherever you are its projection - Gerstner waves in the near grid's vertices (their
// crests sharpened, drawn together), their slopes per pixel everywhere, each faded out
// where it's too far to see (no shimmer).

uniform float ww_t = 0.0;                         // the waves' clock (s: CosmosWaters')
uniform float ww_amp = 0.3;                       // m: the biggest wave's height (the weather's)
uniform vec3 ww_wind = vec3(0.8, 0.12, 0.58);     // planet-local: the way they mostly run
uniform vec3 ww_side = vec3(-0.58, 0.0, 0.8);

const int WW_N = 5;
const float WW_L[5] = float[](31.0, 19.0, 12.0, 7.4, 4.6);      // m: wavelengths
const float WW_A[5] = float[](1.0, 0.6, 0.38, 0.22, 0.12);      // x ww_amp
const float WW_ANG[5] = float[](0.0, 0.55, -0.45, 1.15, -0.9);  // off the wind
const float WW_PH[5] = float[](0.0, 1.7, 4.1, 2.6, 5.3);

vec3 ww_dir(int i) {
	return normalize(ww_wind * cos(WW_ANG[i]) + ww_side * sin(WW_ANG[i]));
}

// Gerstner: the displacement at planet-local `p` (`up` there) and its height (w), `fade` 0 .. 1.
vec4 ww_gerstner(vec3 p, vec3 up, float t, float fade) {
	vec3 disp = vec3(0.0);
	float h = 0.0;
	for (int i = 0; i < WW_N; i++) {
		vec3 D = ww_dir(i);
		vec3 Dt = D - up * dot(D, up);
		float m = length(Dt);
		vec3 dir = Dt / max(m, 1e-4);
		float k = 6.2831853 / WW_L[i];
		float w = sqrt(9.81 * k);
		float A = ww_amp * WW_A[i] * m * fade;
		float ph = k * dot(p, D) - w * t + WW_PH[i];
		float Q = 0.55 / (k * max(ww_amp * WW_A[i], 1e-3) * float(WW_N));
		disp += dir * (Q * A * cos(ph));
		h += A * sin(ph);
	}
	return vec4(disp + up * h, h);
}

// The waves' slope (planet-local, along the ground) at `p`, `dist` m from the eye; `crest`:
// how near a crest it is (0 .. 1, the steepest crests ~1).
vec3 ww_slope(vec3 p, vec3 up, float t, float dist, out float crest) {
	vec3 g = vec3(0.0);
	float c = 0.0;
	for (int i = 0; i < WW_N; i++) {
		vec3 D = ww_dir(i);
		vec3 Dt = D - up * dot(D, up);
		float m = length(Dt);
		vec3 dir = Dt / max(m, 1e-4);
		float fade = 1.0 - smoothstep(WW_L[i] * 22.0, WW_L[i] * 70.0, dist);
		float k = 6.2831853 / WW_L[i];
		float w = sqrt(9.81 * k);
		float A = ww_amp * WW_A[i] * m;
		float ph = k * dot(p, D) - w * t + WW_PH[i];
		g += dir * (A * k * m * cos(ph)) * fade;
		c += WW_A[i] * m * sin(ph);
	}
	crest = clamp(c / 1.6, 0.0, 1.0);
	return g;
}
