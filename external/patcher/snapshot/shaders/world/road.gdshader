shader_type spatial;
render_mode cull_back, depth_draw_opaque;
// A road between a world's towns (CosmosRoads): a ribbon draped over the ground.
// UV.x across (-1..1 the road, past +-0.9 its ragged shoulders - cut out), UV.y
// along it in metres; COLOR.r how paved it is (the stretch out of a city: worn
// cobbles, fading into the earth). Packed earth with two wheel ruts, a grassy
// crown, pebbles; the planet's own soil tints it. Pulled towards the camera a
// little with distance - a depth bias: never lost under the coarser ground far
// off, never shimmering in it close by.

uniform vec3 soil : source_color = vec3(0.45, 0.36, 0.27);
uniform vec3 stone : source_color = vec3(0.6, 0.57, 0.52);
uniform vec3 verge : source_color = vec3(0.33, 0.36, 0.2);

const float HALF = 2.2;   // m: half the road's width (CosmosRoads.WIDTH)

varying vec2 v_uv;
varying float v_paved;

// (Along the road it repeats every PERIOD m, seamlessly: each noise's lattice
// wraps there - its frequencies whole numbers of cells in it - and an integer
// hash: no precision lost thousands of metres along.)
const float PERIOD = 256.0;

float hash(vec2 p, vec2 per) {
	p = mod(p, per);
	uvec2 q = uvec2(ivec2(p) + ivec2(4096));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 15u)) * 2246822519u;
	h ^= h >> 13u;
	return float(h) * (1.0 / 4294967295.0);
}

// Value noise at `k` cells a metre (k * PERIOD whole: it wraps along the road).
float vnoise(vec2 m, float k) {
	vec2 p = m * k;
	vec2 per = vec2(8192.0, PERIOD * k);
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i, per), hash(i + vec2(1.0, 0.0), per), f.x), mix(hash(i + vec2(0.0, 1.0), per), hash(i + vec2(1.0, 1.0), per), f.x), f.y);
}

// Cobbles (in metres): the distance to the nearest stone's edge, and its id - rows
// of irregular setts (2.5 rows a metre: whole in PERIOD), staggered.
vec2 cobbles(vec2 m) {
	vec2 per = vec2(8192.0, PERIOD * 2.5);
	vec2 p = m * vec2(3.4, 2.5);
	float row = mod(floor(p.y), per.y);
	p.x += step(1.0, mod(row, 2.0)) * 0.5 + (hash(vec2(row, 3.0), per) - 0.5) * 0.3;
	vec2 c = floor(p);
	vec2 f = fract(p) + (vec2(hash(c, per), hash(c + vec2(7.0, 0.0), per)) - 0.5) * 0.12;
	float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	return vec2(e, hash(c + vec2(3.0, 0.0), per));
}

// The surface's relief: ruts and pebbles in the earth, the cobbles' joints.
float relief(vec2 m, float pv) {
	float a = abs(m.x) / HALF;
	float rut = exp(-pow((a - 0.42) * 7.0, 2.0));
	float earth = -rut * 0.6 + vnoise(m, 6.0) * 0.35 + vnoise(m, 19.0) * 0.2;
	vec2 cb = cobbles(m);
	float paved = smoothstep(0.0, 0.09, cb.x) * (0.75 + 0.25 * cb.y) + vnoise(m, 14.0) * 0.12;
	return mix(earth, paved, pv);
}

void vertex() {
	v_uv = UV;
	v_paved = COLOR.r;
	vec3 vp = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(vp);
	vp *= max(d - min(0.05 + d * 0.01, d * 0.5), 0.05) / max(d, 0.001);
	POSITION = PROJECTION_MATRIX * vec4(vp, 1.0);
}

void fragment() {
	vec2 m = vec2(v_uv.x * HALF, mod(v_uv.y, PERIOD));   // (metres: across, along)
	float a = abs(v_uv.x);
	float pv = v_paved;
	// Its edge: ragged, eaten by the verge.
	float edge = 1.02 - a + (vnoise(m, 0.75) - 0.5) * 0.3 + (vnoise(m, 5.0) - 0.5) * 0.12;
	ALPHA = smoothstep(0.0, 0.04, edge);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	float n1 = vnoise(m * vec2(3.4, 1.0), 0.375);
	float n2 = vnoise(m, 7.0);
	// Earth: packed, darker in the ruts, grass along the crown, pebbles.
	float rut = exp(-pow((a - 0.42) * 6.0, 2.0));
	float crown = exp(-pow(v_uv.x * 4.5, 2.0));
	vec3 dirt = soil * (0.85 + 0.3 * n1) * (0.92 + 0.16 * n2);
	vec3 earth = mix(dirt, dirt * 0.76, rut * 0.8);
	earth = mix(earth, mix(verge, soil, 0.45), crown * smoothstep(0.35, 0.75, n1) * 0.65);
	float pebble = smoothstep(0.8, 0.9, vnoise(m, 11.0)) * (0.5 + 0.5 * vnoise(m, 31.0));
	earth = mix(earth, stone * (0.7 + 0.25 * n2), pebble * 0.45);
	// Cobbles: grey stones, their joints full of earth, worn smooth in the wheel tracks.
	vec2 cb = cobbles(m);
	vec3 sett = stone * (0.72 + 0.36 * cb.y) * (0.88 + 0.2 * n2);
	vec3 cobbled = mix(dirt * 0.6, sett, smoothstep(0.02, 0.07, cb.x));
	vec3 col = mix(earth, cobbled, pv);
	float rough = mix(0.93 - rut * 0.1, mix(0.95, 0.68 - rut * 0.12, smoothstep(0.02, 0.07, cb.x)), pv);
	// Its verges: the ground's grass and dust closing in at the sides.
	col = mix(col, mix(verge, soil, 0.5), smoothstep(0.8, 1.0, a + (n2 - 0.5) * 0.15) * 0.7);
	ALBEDO = col;
	ROUGHNESS = rough;
	float e = 0.03;
	float h0 = relief(m, pv);
	float hx = relief(m + vec2(e, 0.0), pv);
	float hy = relief(m + vec2(0.0, e), pv);
	NORMAL_MAP = normalize(vec3((h0 - hx) * 0.9, (h0 - hy) * 0.9, 1.0)) * 0.5 + 0.5;
}
