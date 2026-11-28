// The water of a sea world (CosmosPlanet's sea, CosmosWaters' lakes and rivers): what's
// under it seen through it, bent by its waves (the screen behind it, read where its
// waves send the view - not where an object stands in front) and lost into the water's
// colour with depth (red first: clear in the shallows, turquoise, then the deep's blue);
// the sky and the sun off it by the Fresnel law (a few steps along the depth buffer for
// what stands over it - the shore, its trees - reflected near); foam on the crests, at
// the shores and in white water. The sea: a sum of long directional waves (the near grid
// moves them in its vertices: Gerstner waves) and two scales of ripples drifting; a lake:
// small wind ripples; a river: its ripples carried down along it (its mesh's u is metres
// down the river, v across; its colour: speed, rapids, depth, fade), standing waves and
// white water in its rapids, smooth and dark where it's slow.
// `body`: 0 the sea's far sphere (a unit sphere x radius), 1 the sea's near grid (round
// the camera, its vertices waved), 2 a lake, 3 a river. The web's renderer
// (Compatibility): no screen read - the water blended over what's under it.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, ambient_light_disabled;   // (its depth written: the cloud shells behind it hidden - it draws before them; what it reads of the depth and the screen is from before it)

#include "res://shaders/world/water_waves.gdshaderinc"

uniform int body = 0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);   // (world: to the star)
uniform float radius = 3000.0;                 // (the planet's)
uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
#endif
uniform vec4 deep : source_color = vec4(0.02, 0.12, 0.3, 1.0);       // what the deep water scatters back
uniform vec4 shallow : source_color = vec4(0.1, 0.55, 0.6, 1.0);     // (the shallows' tint - the palette's)
uniform vec4 sky_top : source_color = vec4(0.3, 0.55, 0.95, 1.0);    // the sky overhead, reflected
uniform vec4 sky_low : source_color = vec4(0.75, 0.85, 0.95, 1.0);   // ...low round it
uniform vec3 absorb = vec3(0.32, 0.07, 0.045);   // per m: lost into the water (red first)
uniform float murk = 0.06;                       // per m: scattered back (the water's own colour)
uniform float clear_k = 1.0;                     // (how far the view goes in: lakes and rivers less)
uniform float light_k = 1.0;                     // the sun's strength now
uniform vec3 near_c = vec3(0.0, 3000.0, 0.0);    // the near grid's middle (planet-local, on the sphere)
uniform vec3 near_t1 = vec3(1.0, 0.0, 0.0);
uniform vec3 near_t2 = vec3(0.0, 0.0, 1.0);
uniform float near_r = 0.0;                      // its reach (the far sphere leaves it inside that: 0 none)
uniform float obj_scale = 1.0;                   // (the far sphere: a unit sphere - its radius)

varying vec3 v_obj;      // planet-local
varying vec2 v_uv;       // (a river: m down it, across it -1 .. 1)
varying vec4 v_col;      // (a river: speed / 5, rapids, depth / 4, fade)
varying float v_wv;      // (the near grid: its waves' height here, m)
varying float v_spec;    // (to light(): the glints' strength - none on foam)

void vertex() {
	v_col = vec4(0.0, 0.0, 0.5, 1.0);
	v_uv = vec2(0.0);
	v_wv = 0.0;
	if (body == 1) {
		vec3 p = normalize(near_c + near_t1 * VERTEX.x + near_t2 * VERTEX.z) * radius;
		float fade = 1.0 - smoothstep(near_r * 0.3, near_r * 0.8, length(VERTEX.xz));
		vec3 up = normalize(p);
		vec4 g = ww_gerstner(p, up, ww_t, fade);
		v_wv = g.w;
		p += g.xyz;
		VERTEX = p;    // (the grid's node sits on the planet's: planet-local)
		v_obj = p;
	} else if (body == 0) {
		v_obj = VERTEX * obj_scale;
	} else {
		v_obj = VERTEX;
		v_uv = UV;
		v_col = COLOR;
	}
}

float nz(vec3 p) {
	return texture(noise_tex, p).r;
}

// A ripple field's slope (planet-local, along the ground) at `q` (noise space), `s` m a unit:
// two lookups of the noise, offset, its two slopes (cheap - a pixel of sea does a few).
vec3 ripple(vec3 q, vec3 t1, vec3 t2, float s) {
	return (t1 * (nz(q) - 0.5) + t2 * (nz(q.yzx + 0.37) - 0.5)) * (1.4 / s);
}

// What's at screen `uv`, in the view's space, from the depth buffer (w: 1 something's there, 0 the sky).
vec4 view_at(vec2 uv, mat4 inv_proj) {
	float z = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	bool hit = z < 1.0;
	z = z * 2.0 - 1.0;
#else
	bool hit = z > 0.0;
#endif
	if (!hit) {
		return vec4(0.0, 0.0, -1e6, 0.0);
	}
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, z, 1.0);
	return vec4(v.xyz / v.w, 1.0);
}

void fragment() {
	vec3 up = normalize(v_obj);
	float dist = length(VERTEX);
	if (body == 0 && near_r > 0.0 && length(v_obj - near_c) < near_r * 0.9) {
		discard;   // (the near grid's)
	}
	// The ground's frame here (planet-local), and the water's slope - its waves, its ripples.
	vec3 t1 = normalize(cross(up, abs(up.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 t2 = cross(up, t1);
	vec3 slope = vec3(0.0);
	float foam = 0.0;
	float rapid = 0.0;
	float near = 1.0 - smoothstep(60.0, 700.0, dist);
	float fine = 1.0 - smoothstep(8.0, 90.0, dist);
	if (body <= 1) {
		float crest;
		slope = ww_slope(v_obj, up, ww_t, dist, crest);
		vec3 q = v_obj / 9.0 + vec3(ww_t * 0.031, 0.0, ww_t * 0.022);
		slope += ripple(q, t1, t2, 9.0) * 0.55 * near;
		vec3 q2 = v_obj / 2.3 - vec3(0.0, ww_t * 0.06, ww_t * 0.045);
		slope += ripple(q2, t1, t2, 2.3) * 0.22 * fine;
		// (whitecaps: on the steepest crests, sparse, broken up)
		// (whitecaps: only when the wind's up - the waves high - on the steepest crests, broken up)
		float windy = smoothstep(0.45, 1.1, ww_amp);
		float cap = smoothstep(0.7, 0.98, crest + (nz(v_obj / 6.0 + ww_t * 0.04) - 0.5) * 0.5);
		foam = cap * smoothstep(0.5, 0.68, nz(v_obj / 1.7 - vec3(ww_t * 0.12))) * near * windy;
		if (body == 1) {
			foam = max(foam, smoothstep(0.55, 0.8, v_wv / max(ww_amp, 0.05)) * smoothstep(0.58, 0.74, nz(v_obj / 2.1 + ww_t * 0.07)) * (0.15 + 0.6 * windy));
		}
	} else if (body == 2) {
		vec3 q = v_obj / 4.0 + vec3(ww_t * 0.05, 0.0, ww_t * 0.035);
		slope = ripple(q, t1, t2, 4.0) * 0.16 * near;
		vec3 q2 = v_obj / 1.2 - vec3(0.0, ww_t * 0.09, ww_t * 0.06);
		slope += ripple(q2, t1, t2, 1.2) * 0.07 * fine;
	} else {
		// A river: its ripples carried along it (the mesh's u: m from its spring - the
		// flow's own coordinate), standing waves and white water where it's fast.
		float spd = v_col.r * 5.0;
		rapid = v_col.g;
		// (downstream: the way its u grows - from the screen's derivatives, no tangents needed)
		vec3 dp1 = dFdx(v_obj);
		vec3 dp2 = dFdy(v_obj);
		vec3 gu = cross(dp2, up) * dFdx(v_uv.x) + cross(up, dp1) * dFdy(v_uv.x);
		vec3 f = normalize(gu - up * dot(gu, up) + t1 * 1e-6);
		vec3 s2 = cross(up, f);
		float along = v_uv.x;
		float across = v_uv.y;
		float scroll = along - ww_t * spd;
		vec3 q = vec3(scroll / 3.5, across * 1.3, 0.37);
		float e = 0.05;
		float h0 = nz(q);
		vec3 g = f * (nz(q + vec3(e, 0.0, 0.0)) - h0) / (e * 3.5) + s2 * (nz(q + vec3(0.0, e, 0.0)) - h0) / (e * 3.5 / 1.3 * 6.0);
		vec3 q2 = vec3((along - ww_t * spd * 1.3) / 1.1, across * 3.1 + 0.5, 0.71);
		float k0 = nz(q2);
		g += f * (nz(q2 + vec3(e, 0.0, 0.0)) - k0) / (e * 1.1) * 0.5;
		slope = g * mix(0.12, 0.45, rapid) * near;
		// (standing waves: their crests across the flow, fixed where the bed throws them up)
		float sw = sin(along * 1.9 + nz(vec3(along / 7.0, across, 0.2)) * 6.0);
		slope += f * cos(along * 1.9) * 0.35 * rapid * near;
		// (white water: streaks drawn out along the flow, churning, thickest over the standing
		// waves and by the banks; elsewhere the odd fleck of foam drifting down)
		float churn = nz(vec3(scroll / 5.0, across * 1.6, ww_t * 0.3)) * 0.65 + nz(vec3(scroll / 1.3, across * 3.5, ww_t * 0.5)) * 0.35;
		float wf = smoothstep(0.66 - rapid * 0.14, 0.82 - rapid * 0.1, churn + sw * 0.1 * rapid);
		foam = wf * rapid * rapid;
		foam = max(foam, smoothstep(0.78, 0.98, abs(across)) * rapid * smoothstep(0.5, 0.68, churn));
		foam = max(foam, smoothstep(0.86, 0.93, nz(vec3(scroll / 0.9, across * 4.0, 0.9))) * (0.25 + 0.4 * rapid));   // (flecks drifting by)
	}
	vec3 upw = normalize(mat3(MODEL_MATRIX) * up);
	vec3 upv = normalize(mat3(VIEW_MATRIX) * upw);
	vec3 V = normalize(-VERTEX);
	// (seen low across it, its ripples blend into one sheen: no speckle at the horizon)
	slope *= mix(0.3, 1.0, smoothstep(0.02, 0.35, abs(dot(upv, V))));
	vec3 wn = normalize(up - slope);
	vec3 nw = normalize(mat3(MODEL_MATRIX) * wn);
	NORMAL = normalize(mat3(VIEW_MATRIX) * nw);
	float cosv = clamp(dot(NORMAL, V), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - cosv, 5.0);
	float day = smoothstep(-0.12, 0.25, dot(sun_dir, upw)) * light_k;

	// What's under it: the screen behind, bent by the waves (not to what stands in front of it).
	vec4 vf = view_at(SCREEN_UV, INV_PROJECTION_MATRIX);
	float toward = clamp((length(vf.xyz) - dist) * 0.3, 0.0, 1.0);
	vec2 bend = (NORMAL.xy - upv.xy) * 0.07 * toward / (1.0 + dist * 0.03);
	vec2 uv2 = SCREEN_UV + bend;
	vec4 vf2 = view_at(uv2, INV_PROJECTION_MATRIX);
	if (vf2.w > 0.5 && length(vf2.xyz) < dist) {
		uv2 = SCREEN_UV;   // (in front of the water there: not bent)
		vf2 = vf;
	}
	float t_view = vf2.w > 0.5 ? max(length(vf2.xyz) - dist, 0.0) : 1e4;
	// (the floor's own depth under the surface: the sunlight already lost on its way down to it)
	float t_down = vf2.w > 0.5 ? max(dot(VERTEX - vf2.xyz, upv), 0.0) : 1e4;
	vec3 trans = exp(-absorb * (t_view * clear_k + t_down));
	float scat = 1.0 - exp(-murk * t_view * clear_k);
	vec3 water_c = mix(deep.rgb, deep.rgb * 0.5 + shallow.rgb * 0.5, exp(-t_view * 0.08)) * (0.15 + 0.85 * day);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	vec3 under = vf2.w > 0.5 ? texture(screen_tex, uv2).rgb : vec3(0.0);
	vec3 refr = under * trans + water_c * scat * (1.0 - trans * 0.6);
#else
	vec3 refr = water_c;   // (the web: blended over what's under it, by how deep)
#endif

	// The sky and what stands near over it, mirrored.
	vec3 R = reflect(-V, NORMAL);
	vec3 Rw = mat3(INV_VIEW_MATRIX) * R;
	float el = dot(Rw, upw);
	float sd = max(dot(Rw, sun_dir), 0.0);
	vec3 sky = mix(sky_low.rgb, sky_top.rgb, smoothstep(-0.05, 0.6, el)) * (0.06 + 0.94 * day);
	sky += vec3(1.0, 0.85, 0.65) * pow(sd, 12.0) * 0.4 * day;   // (the glow round the sun)
	vec3 refl = sky;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	if (dist < 200.0 && el > -0.02 && fres * smoothstep(0.0, 0.25, t_view) > 0.06) {   // (only where the reflection shows)
		// (a few steps up the reflected ray against the depth buffer: the shore, its trees, a hull)
		float jit = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		float len = 4.0 + dist * 0.9;
		vec3 hit = vec3(0.0);
		float got = 0.0;
		for (int i = 1; i <= 7; i++) {
			float s = pow((float(i) - 0.5 + jit * 0.5) / 7.0, 1.6) * len;
			vec3 p = VERTEX + R * s;
			vec4 cp = PROJECTION_MATRIX * vec4(p, 1.0);
			if (cp.w <= 0.0) break;
			vec2 suv = cp.xy / cp.w * 0.5 + 0.5;
			if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) break;
			vec4 sv = view_at(suv, INV_PROJECTION_MATRIX);
			float behind = length(p) - length(sv.xyz);
			if (sv.w > 0.5 && behind > 0.0 && behind < max(2.0, s * 0.35)) {
				vec2 e2 = min(suv, 1.0 - suv);
				got = smoothstep(0.0, 0.08, min(e2.x, e2.y)) * (1.0 - smoothstep(120.0, 200.0, dist));
				hit = texture(screen_tex, suv).rgb;
				break;
			}
		}
		refl = mix(refl, hit, got);
	}
#endif

	// Foam: at the shores (the ground just under the surface), on the crests, white water.
	float shore = 1.0 - smoothstep(0.0, 1.1, t_down);
	if (t_view < 1e4 && body != 3) {
		float lace = smoothstep(0.38, 0.62, nz(v_obj / 1.4 + vec3(0.0, ww_t * 0.05, 0.0)) + 0.25 * sin(ww_t * 1.3 + t_down * 5.0));
		foam = max(foam, shore * lace * (body == 2 ? 0.35 : 0.8));
	}
	foam = clamp(foam, 0.0, 1.0);
	float edge = smoothstep(0.0, 0.25, t_view);   // (where it meets the ground: no seam)
	vec3 col = mix(refr, refl, fres * edge);
	v_spec = (1.0 - foam) * edge;
	ALBEDO = vec3(0.9, 0.93, 0.95) * foam;
	EMISSION = col * (1.0 - foam) + foam * (sky_top.rgb * 0.25 + sky_low.rgb * 0.15) * (0.08 + 0.92 * day);   // (foam: the sky's light on it too)
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	ALPHA = v_col.a;
#else
	ALPHA = v_col.a * clamp(max(1.0 - (trans.r + trans.g + trans.b) / 3.0, fres) + foam, 0.0, 1.0) * edge;
#endif
}

void light() {
	// (the sun: this world's own way to it; the rest - your lamp, a torch - from where they are)
	vec3 L = LIGHT_IS_DIRECTIONAL ? normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz) : LIGHT;
	float ndl = clamp(dot(NORMAL, L), 0.0, 1.0);
	DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR / PI;   // (only the foam has a colour of its own)
	vec3 H = normalize(L + VIEW);
	float nh = clamp(dot(NORMAL, H), 0.0, 1.0);
	float fr = 0.02 + 0.98 * pow(1.0 - clamp(dot(H, VIEW), 0.0, 1.0), 5.0);
	float s = pow(nh, 2400.0) * 70.0 + pow(nh, 260.0) * 1.6;   // (the glints: a sharp core, a sheen round it)
	SPECULAR_LIGHT += s * fr * smoothstep(0.0, 0.08, ndl) * v_spec * ATTENUATION * LIGHT_COLOR / PI;
}
