// The plants' shader (flora.gdshader, leaf_flora.gdshader - with LEAF_CARDS: its leaf cards cut into leaves).
// A planet's plants (CosmosFlora, scattered by CosmosPlanet): vertex colours,
// a glow where a species glows (UV.x: crystals, some fungi), swaying in the
// wind - more the higher up the plant (UV.y: how far the vertex sways), each
// plant in its own rhythm (its place). Leaves (UV2.x 1) flutter, let the light
// through (backlit) and are a touch glossier than bark; grass and flowers
// (UV2.y: a distance) shrink away into the ground before it - each plant at its
// own distance, so a meadow thins out rather than ends. Each plant its own
// shade (from its turn - steady under the floating origin). Leaf cards
// (UV2.x 3 + u, 5 + u: pale beneath; UV2.y -(1 + 2 type + v)) are cut into
// leaves here: sprays of narrow (olive) or oval (oak) leaves along a stalk,
// one broad lobed leaf (plane, fig), a fan of pine needles, a cypress's
// scale-leaf frond - each leaf its own shade (CosmosFlora.M.card).

uniform float wind = 1.0;

varying float v_leaf;
varying vec3 v_tint;
varying vec3 v_local;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// (value noise: the leaves' grain - clusters of leaves and the gaps between)
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

#ifdef LEAF_CARDS
// One leaf on a card (p: x across -0.5..0.5, y along 0..1): from `base` at `ang`
// (from the stalk), `len` long, `wid` wide at its widest.
bool leaf(vec2 p, vec2 base, float ang, float len, float wid) {
	vec2 ax = vec2(sin(ang), cos(ang));
	vec2 d = p - base;
	float t = dot(d, ax) / len;
	if (t < 0.0 || t > 1.0) {
		return false;
	}
	float w = wid * pow(sin(3.14159 * t), 0.75) * (1.0 - 0.25 * t);
	return abs(d.x * ax.y - d.y * ax.x) < w;
}

// The card's leaves: -1 none here (cut away), else which leaf (its shade).
float leaves(vec2 uv, float type) {
	vec2 p = vec2(uv.x - 0.5, uv.y);
	if (type < 1.5) {
		// A stalk and its leaves: olive's opposite pairs of narrow ones, oak's alternate ovals.
		bool lance = type < 0.5;
		if (abs(p.x) < 0.012 && p.y < 0.82) {
			return 0.0;
		}
		float n = lance ? 4.0 : 5.0;
		for (float i = 0.0; i < 5.0; i += 1.0) {
			if (i >= n) {
				break;
			}
			float y = 0.08 + i * 0.7 / n;
			float a = 0.95 - 0.35 * i / n;
			float len = (lance ? 0.4 : 0.36) * (1.0 - 0.15 * i / n);
			float wid = lance ? 0.055 : 0.12;
			if (lance || mod(i, 2.0) < 0.5) {
				if (leaf(p, vec2(0.0, y), a, len, wid)) return 1.0 + i;
			}
			if (lance || mod(i, 2.0) > 0.5) {
				if (leaf(p, vec2(0.0, y + (lance ? 0.0 : 0.05)), -a, len, wid)) return 11.0 + i;
			}
		}
		if (leaf(p, vec2(0.0, 0.74), 0.0, 0.26, lance ? 0.05 : 0.1)) return 21.0;
		return -1.0;
	} else if (type < 2.5) {
		// One broad leaf, five-lobed (plane, fig), on its stalk.
		if (abs(p.x) < 0.015 && p.y < 0.4) {
			return 0.0;
		}
		vec2 d = p - vec2(0.0, 0.52);
		float th = atan(d.x, d.y);
		float r = length(d);
		float lobe = 0.62 + 0.38 * pow(abs(cos(th * 2.5)), 0.7);
		if (abs(th) > 2.7 || r > 0.47 * lobe) {
			return -1.0;
		}
		return 1.0 + floor((th + 3.2) * 0.8);
	} else if (type < 3.5) {
		// Pine needles: a fan of fine lines from the twig's end.
		vec2 d = p - vec2(0.0, 0.04);
		float r = length(d);
		float th = atan(d.x, d.y);
		if (abs(th) > 1.05 || r > 0.94 - 0.2 * abs(th) || r < 0.03) {
			return -1.0;
		}
		float k = th * 7.0;
		float off = abs(fract(k + 0.5) - 0.5) / 7.0 * r;
		return off < 0.006 + 0.008 * (1.0 - r) ? 1.0 + floor(k + 0.5) + 8.0 : -1.0;
	}
	// A cypress's (fir's) frond: scale-leaf branchlets either side of a stem.
	float w = 0.44 * pow(sin(3.14159 * p.y), 0.6);
	if (abs(p.x) > w) {
		return -1.0;
	}
	if (abs(p.x) < 0.02) {
		return 0.0;
	}
	float y = p.y - abs(p.x) * 0.85;
	return fract(y * 11.0) < 0.62 ? 1.0 + floor(y * 11.0) : -1.0;
}

#endif

void vertex() {
	vec3 at = MODEL_MATRIX[3].xyz;
	v_local = VERTEX;
	float ph = dot(at, vec3(0.13, 0.07, 0.11));
	float own = hash3(MODEL_MATRIX[0].xyz * 7.3);
	if (UV2.y > 0.0) {
		float dist = distance(at, INV_VIEW_MATRIX[3].xyz);
		float far = UV2.y * (0.55 + 0.45 * own);
		VERTEX *= 1.0 - smoothstep(far * 0.72, far, dist);
	}
	float k = UV.x > 0.9 ? 0.0 : wind * 0.04 * pow(max(UV.y, 0.0), 1.3);
	VERTEX.x += sin(TIME * 1.7 + ph) * k;
	VERTEX.z += cos(TIME * 1.3 + ph * 1.7) * k * 0.7;
	if (UV2.x > 0.5 && UV.x < 0.9) {
		float f = wind * 0.012 * min(UV.y, 3.0);
		VERTEX += vec3(sin(TIME * 5.3 + VERTEX.y * 3.1 + ph), sin(TIME * 4.1 + VERTEX.x * 2.7), cos(TIME * 6.1 + VERTEX.z * 3.3 + ph)) * f;
	}
	v_leaf = min(UV2.x, 1.0);
	float o2 = hash3(MODEL_MATRIX[2].xyz * 5.1);
	v_tint = vec3(0.88 + 0.24 * own, 0.9 + 0.2 * mix(own, o2, 0.5), 0.88 + 0.18 * o2);
}

void fragment() {
	// (vertex colours are sRGB - as the terrain's colours are: to linear)
	vec3 sc = COLOR.rgb * v_tint;
	vec3 c = mix(pow((sc + 0.055) / 1.055, vec3(2.4)), sc / 12.92, step(sc, vec3(0.04045)));
#ifdef LEAF_CARDS
	if (UV2.x > 2.5) {
		// A leaf card: cut into its leaves, each its own shade; pale beneath (olive).
		float q = -UV2.y - 1.0;
		float type = floor(q * 0.5 + 0.001);
		vec2 uv = vec2(fract(UV2.x), clamp(q - type * 2.0, 0.0, 1.0));
		float id = leaves(uv, type);
		if (id < 0.0) {
			discard;
		}
		c *= id < 0.5 ? 0.6 : 0.8 + 0.4 * hash3(vec3(id, v_tint.x * 13.0, v_tint.z * 7.0));
		if (!FRONT_FACING && UV2.x > 4.5) {
			c = mix(c, vec3(dot(c, vec3(0.3, 0.5, 0.2))) * 1.9, 0.65);
		}
	} else
#endif
	if (v_leaf > 0.5 && UV2.y <= 0.0) {
		// Leaves: clusters and gaps (darker), their facing broken up - not one smooth skin.
		float n1 = vnoise(v_local * 3.1);
		float n2 = vnoise(v_local * 7.3 + 11.0);
		float g = n1 * 0.6 + n2 * 0.4;
		c *= 0.55 + 0.75 * g;
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(vec3(n2 - 0.5, n1 - 0.5, 0.5 - n2) * 1.2, 0.0)).xyz);
	}
	ALBEDO = c;
	ROUGHNESS = mix(0.9, 0.68, v_leaf);
	SPECULAR = 0.35;
	BACKLIGHT = c * 0.45 * v_leaf;
	EMISSION = c * UV.x * 2.2;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;     // (blades and leaves: both sides)
	}
}
