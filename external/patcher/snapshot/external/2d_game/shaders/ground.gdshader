// Procedural planet ground for the isometric surface view. Drawn on one
// polygon covering the whole map. Terrain comes from a smoothed height map
// (one texel per map cell, same values the game uses for walkability), so
// borders are organic instead of following the tile grid. Each terrain kind
// gets its own detail pattern, and a micro-relief bump map is lit from the
// upper left. The broad relief is hillshaded from the height map (light from
// the upper left), and limestone crags (the map's green channel - the same
// bytes PlanetSurface._ground_ok blocks) stand up with a cliff face below.
shader_type canvas_item;

#include "res://shaders/noise.gdshaderinc"

uniform sampler2D height_map : filter_linear, repeat_disable;
uniform float grid_n = 44.0;
// World position -> fractional grid coordinates.
uniform vec2 inv_x;
uniform vec2 inv_y;
uniform vec2 inv_o;
uniform int count = 4;
uniform vec4 colors[8] : source_color;
uniform int kinds[8];            // index into Planets.GROUND_KINDS
uniform float thresholds[8];     // height boundaries between terrains
uniform float seed = 0.0;
uniform vec4 rock_color : source_color = vec4(0.74, 0.71, 0.64, 1.0);
// The map: R height, G solid rock (crags and cliffs), B ramp (ledges meet in
// slopes), A crags. The mesh is lifted by the elevation - SurfaceTerrain's
// ledges, computed here from the filtered map exactly as the game does.
uniform float rock_solid = 0.4;
uniform float cliff_px = 22.0;
uniform float terrace_h = 0.2;
uniform float step_px = 110.0;
uniform float cliff_w = 0.05;
uniform float crag_h = 72.0;
uniform float rim_tiles = 10.0;
uniform float water_top = -1.0;
uniform float site_h = 0.0;
uniform float rim_lift = 0.0;
uniform float t0 = 0.0;
// The fine window near the camera (fine_mesh = true): its vertices are grid
// coordinates from win_origin; the coarse whole-map mesh leaves it out.
uniform bool fine_mesh = false;
uniform vec2 win_origin = vec2(-99999.0);
uniform float win_size = 100.0;
uniform vec2 g2w_x;
uniform vec2 g2w_y;
uniform vec2 g2w_o;

varying vec2 wpos;
varying vec2 spos;
varying vec2 slope;
varying float vramp;  // ramps are ways up between ledges: never walls  // the elevation's climb per tile along the grid's x and y (px), from the vertex   // where it's drawn (lifted): cliff faces are textured upright

const int WATER = 0;
const int SAND = 1;
const int GRASS = 2;
const int FOREST = 3;
const int REGOLITH = 4;
const int CRATER = 5;
const int ICE = 6;
const int SNOW = 7;
const int CREVASSE = 8;

vec2 to_grid(vec2 p) {
	return inv_x * p.x + inv_y * p.y + inv_o;
}

float terr(float x, float ramp) {
	float f = x - floor(x);
	float s = 0.15 * f + 0.85 * smoothstep(1.0 - cliff_w, 1.0, f);
	return floor(x) + mix(s, f, ramp);
}

// Screen px the ground stands up at grid point g (SurfaceTerrain.elevation).
float elevation(vec2 g) {
	vec4 m = textureLod(height_map, (g + 0.5) / grid_n, 0.0);
	float h = m.r * 2.0 - 1.0;
	float x = (max(h, water_top) - site_h) / terrace_h;
	float e = step_px * (terr(x, m.b) - t0) + crag_h * smoothstep(rock_solid, 0.7, m.a);
	float edge = min(min(g.x + 0.5, g.y + 0.5), min(grid_n - 0.5 - g.x, grid_n - 0.5 - g.y));
	return mix(rim_lift, e, smoothstep(0.0, rim_tiles, edge));
}

void vertex() {
	vec2 g;
	if (fine_mesh) {
		g = clamp(VERTEX + win_origin, vec2(-0.5), vec2(grid_n - 0.5));
		VERTEX = g2w_x * g.x + g2w_y * g.y + g2w_o;
	} else {
		g = to_grid(VERTEX);
	}
	wpos = VERTEX;   // (the ground plane: what the game's coordinates are)
	float e = elevation(g);
	vramp = textureLod(height_map, (g + 0.5) / grid_n, 0.0).b;
	slope = vec2(elevation(g + vec2(0.12, 0.0)) - e, elevation(g + vec2(0.0, 0.12)) - e) / 0.12;
	VERTEX.y -= e;
	spos = VERTEX;
}

float height_at(vec2 p) {
	vec2 uv = (to_grid(p) + 0.5) / grid_n;
	float h = texture(height_map, uv).r * 2.0 - 1.0;
	// Organic edges, so borders don't follow the grid.
	return h + (fbm(p * 0.006 + seed) - 0.5) * 0.07;
}

// The crag field (0..1; solid from 0.5), filtered like the game's rock_interp.
float rock_at(vec2 p) {
	return texture(height_map, (to_grid(p) + 0.5) / grid_n).g;
}


// The crags' look (0..1).
float crag_at(vec2 p) {
	return texture(height_map, (to_grid(p) + 0.5) / grid_n).a;
}

// Raw height at grid coordinates (no edge noise): the broad relief.
float relief(vec2 g) {
	return texture(height_map, (g + 0.5) / grid_n).r * 2.0 - 1.0;
}

// Small round stones scattered on a jittered grid.
float pebbles(vec2 p, float cell, float chance) {
	vec2 c = floor(p / cell);
	vec2 f = fract(p / cell);
	vec2 centre = vec2(hash21(c + 3.1), hash21(c + 8.7)) * 0.6 + 0.2;
	float r = 0.12 + 0.12 * hash21(c + 1.9);
	float d = length((f - centre) * vec2(1.0, 2.0));   // squashed for the iso view
	return (hash21(c) < chance) ? 1.0 - smoothstep(r * 0.7, r, d) : 0.0;
}

int band(float h) {
	int t = 0;
	for (int i = 0; i < count - 1; i++) {
		if (h > thresholds[i]) {
			t = i + 1;
		}
	}
	return t;
}

bool wet(int t) {
	return kinds[t] == WATER || kinds[t] == CREVASSE;
}

// Limestone: the top of a crag (rim: 0 at its edge .. 1 well inside).
vec3 crag_top(vec2 p, float rim) {
	vec3 col = rock_color.rgb * (0.82 + 0.3 * fbm(p * 0.01 + seed));
	col *= 0.92 + 0.12 * hash21(floor(p * 0.5));
	float crack = 1.0 - smoothstep(0.0, 0.022, abs(fbm(p * 0.014 + 5.0) - 0.5));
	col = mix(col, col * 0.55, crack * 0.8);
	float pb = pebbles(p, 16.0, 0.3);
	col = mix(col, col * 1.12, pb * 0.5);
	// Bevel: the rock's own slope lit from the upper left, a bright lip at
	// the edge, darker deep in (weathered).
	vec2 e = vec2(10.0, 0.0);
	float gx = rock_at(p + e.xy) - rock_at(p - e.xy);
	float gy = rock_at(p + e.yx) - rock_at(p - e.yx);
	col *= 1.0 + clamp((gx * 0.8 + gy) * 2.2, -0.35, 0.35);
	col *= mix(1.22, 0.95, rim);
	return col;
}

// The cliff face below a crag: `down` 0 just under the edge .. 1 at its foot.
// A limestone cliff, upright on screen (q: screen position): courses of
// blocks with joints, each block its own shade, a sunlit top edge and a dark
// joint below, weathering stains.
vec3 cliff_face(vec2 q, float lit) {
	float row_h = 34.0;
	float yy = q.y + 8.0 * fbm(vec2(q.x * 0.01, 1.0));                // courses wander
	float row = floor(yy / row_h);
	float fy = fract(yy / row_h);
	float w = 60.0 + 70.0 * hash21(vec2(row, 7.0));
	float x = q.x / w + hash21(vec2(row, 3.0));
	float blk = floor(x);
	float fx = fract(x);
	vec3 col = rock_color.rgb * (0.72 + 0.28 * hash21(vec2(blk, row)));
	col *= 0.9 + 0.2 * fbm(q * 0.03 + seed);                          // stains
	col *= mix(0.7, 1.0, smoothstep(0.0, 0.1, fy));                   // the joint above (shadow)
	col = mix(col, col * 1.25, smoothstep(0.1, 0.0, abs(fy - 0.14)) * 0.6);   // the sunlit top edge of the course
	col *= mix(0.75, 1.0, smoothstep(0.0, 0.03, min(fx, 1.0 - fx)) + step(0.55, hash21(vec2(blk, row + 9.0))));  // vertical joints (some blocks run on)
	float crack = 1.0 - smoothstep(0.0, 0.03, abs(fbm(vec2(q.x * 0.02, q.y * 0.006) + 4.0) - 0.5));
	col = mix(col, col * 0.6, crack * 0.6);
	return col * lit;
}

vec3 crag_face(vec2 p, float down) {
	vec3 col = rock_color.rgb * mix(0.62, 0.3, down * down);
	float fis = fbm(vec2(p.x * 0.06, p.y * 0.006) + seed);          // vertical fissures
	col *= 0.78 + 0.4 * smoothstep(0.3, 0.7, fis);
	col *= 0.94 + 0.06 * sin(p.y * 0.35 + fbm(p * 0.02) * 5.0);     // strata
	return col;
}

vec3 ground_detail(int kind, vec3 base, vec2 p, float shore) {
	vec3 col = base;
	if (kind == WATER) {
		float w = fbm(p * 0.008 + vec2(TIME * 0.03, TIME * 0.02));
		float waves = sin(p.x * 0.045 + p.y * 0.09 + w * 7.0 + TIME * 1.3) * 0.5 + 0.5;
		col = base * (0.82 + 0.3 * w);
		col += vec3(0.05, 0.07, 0.08) * smoothstep(0.82, 1.0, waves);
		// Glints.
		col += vec3(0.25) * step(0.996, hash21(floor(p * 0.35) + floor(TIME * 2.0)));
		// Foam where water meets land.
		float foam = (1.0 - smoothstep(0.0, 0.035, shore));
		foam *= 0.55 + 0.45 * sin(TIME * 2.0 + p.x * 0.04 + w * 8.0);
		col = mix(col, vec3(0.9, 0.96, 1.0), clamp(foam, 0.0, 1.0) * 0.7);
	} else if (kind == SAND) {
		float ripple = sin(p.x * 0.11 + p.y * 0.23 + fbm(p * 0.015) * 7.0) * 0.5 + 0.5;
		col = base * (0.9 + 0.12 * ripple + 0.1 * (fbm(p * 0.01) - 0.5));
		float grain = hash21(floor(p * 0.6));
		col *= 0.95 + 0.1 * grain;
		col = mix(col, base * 0.75, pebbles(p, 22.0, 0.06) * 0.8);
	} else if (kind == GRASS || kind == FOREST) {
		float patches = fbm(p * 0.005);
		float fine = fbm(p * 0.04);
		col = base * (0.78 + 0.4 * patches);
		// Dry, yellowish patches and darker lush ones.
		col = mix(col, col * vec3(1.18, 1.1, 0.68), smoothstep(0.58, 0.75, fine) * 0.45);
		col = mix(col, col * vec3(0.75, 0.9, 0.75), smoothstep(0.35, 0.2, fine) * 0.4);
		// Blade texture: short vertical streaks.
		float blade = hash21(floor(p * vec2(0.8, 0.3)));
		col *= 0.88 + 0.22 * blade;
		if (kind == FOREST) {
			col *= 0.8;
			// Leaf litter.
			float leaf = step(0.93, hash21(floor(p * 0.45) + 5.0));
			col = mix(col, vec3(0.42, 0.3, 0.14), leaf * 0.5);
		} else {
			// Tiny flowers.
			float f = hash21(floor(p * 0.28) + 11.0);
			if (f > 0.993) {
				vec3 petal = (f > 0.997) ? vec3(1.0, 0.95, 0.6) : vec3(1.0, 0.6, 0.8);
				col = mix(col, petal, 0.85);
			}
		}
	} else if (kind == REGOLITH || kind == CRATER) {
		float n = fbm(p * 0.008);
		col = base * (0.8 + 0.4 * n);
		col *= 0.93 + 0.14 * hash21(floor(p * 0.7));
		// Pebbles: lit top-left, shaded bottom-right.
		float pb = pebbles(p, 18.0, 0.25);
		float pb_shade = pebbles(p + vec2(-2.0, -1.5), 18.0, 0.25);
		col = mix(col, col * 1.3, pb * 0.6);
		col = mix(col, col * 0.6, clamp(pb_shade - pb, 0.0, 1.0) * 0.7);
		// Micro-craters.
		vec2 cc = floor(p / 90.0);
		vec2 cf = fract(p / 90.0);
		vec2 centre = vec2(hash21(cc + 2.0), hash21(cc + 9.0)) * 0.5 + 0.25;
		float d = length((cf - centre) * vec2(1.0, 2.0));
		float rad = 0.12 + 0.12 * hash21(cc + 4.0);
		if (hash21(cc + 6.0) < (kind == CRATER ? 0.75 : 0.35)) {
			col *= 1.0 - 0.35 * (1.0 - smoothstep(rad * 0.6, rad, d));        // dark pit
			col *= 1.0 + 0.25 * smoothstep(rad * 0.85, rad, d) * (1.0 - smoothstep(rad, rad * 1.25, d)); // bright rim
		}
	} else if (kind == ICE) {
		float n = fbm(p * 0.006);
		col = base * (0.88 + 0.25 * n);
		// Branching cracks.
		float c1 = 1.0 - smoothstep(0.0, 0.018, abs(fbm(p * 0.007 + 3.0) - 0.5));
		float c2 = 1.0 - smoothstep(0.0, 0.012, abs(fbm(p * 0.02 + 9.0) - 0.5));
		col = mix(col, base * 0.55 + vec3(0.0, 0.04, 0.1), clamp(c1 * 0.8 + c2 * 0.4, 0.0, 1.0));
		// Moving sheen.
		float sheen = smoothstep(0.75, 1.0, sin((p.x + p.y * 2.0) * 0.006 + n * 4.0 + TIME * 0.4));
		col += vec3(0.12, 0.14, 0.16) * sheen;
	} else if (kind == SNOW) {
		float drift = fbm(p * 0.005);
		col = base * (0.88 + 0.14 * drift);
		col *= 0.97 + 0.04 * hash21(floor(p * 0.5));
		// Sparkles that twinkle.
		float s = hash21(floor(p * 0.4));
		if (s > 0.994) {
			col += vec3(0.35) * (0.5 + 0.5 * sin(TIME * 4.0 + s * 60.0));
		}
	} else if (kind == CREVASSE) {
		float depth = clamp(shore * 6.0, 0.0, 1.0);   // further from the edge = deeper
		col = mix(base * 1.4, base * 0.35, depth);
		col += vec3(0.0, 0.05, 0.1) * fbm(p * 0.02);
	}
	return col;
}

void fragment() {
	vec2 p = wpos;
	vec2 g = to_grid(p);
	if (g.x < -0.5 || g.y < -0.5 || g.x > grid_n - 0.5 || g.y > grid_n - 0.5) {
		discard;
	}
	if (!fine_mesh && all(greaterThan(g, win_origin + 0.5)) && all(lessThan(g, win_origin + win_size - 1.5))) {
		discard;   // (the fine mesh draws here)
	}
	float h = height_at(p);
	// The edge noise never moves the shore: water / crevasse exactly where the
	// game's walkability (the plain filtered height) says.
	float h0 = relief(g);
	if (wet(band(h0)) != wet(band(h))) {
		h = h0;
	}

	// Which terrain band are we in, and how close to the next one?
	int t = 0;
	for (int i = 0; i < count - 1; i++) {
		if (h > thresholds[i]) {
			t = i + 1;
		}
	}
	float upper = (t < count - 1) ? thresholds[t] : 9.0;
	float lower = (t > 0) ? thresholds[t - 1] : -9.0;
	float shore = upper - h;  // distance to the next band up
	// Foam / crevasse depth only matter toward land of a different kind.
	if (t < count - 1 && kinds[t + 1] == kinds[t]) {
		shore = 1.0;
	}
	if (kinds[t] == CREVASSE) {
		shore = upper - h;
	}

	vec3 col = ground_detail(kinds[t], colors[t].rgb, p, shore);

	// Soft blend into the band below, so borders aren't hard lines.
	float blend = 1.0 - smoothstep(0.0, 0.025, h - lower);
	if (t > 0 && blend > 0.0 && kinds[t - 1] != WATER && kinds[t - 1] != CREVASSE) {
		vec3 below = ground_detail(kinds[t - 1], colors[t - 1].rgb, p, 1.0);
		col = mix(col, below, blend * 0.5);
	}

	// Micro relief lit from the upper left (not on water).
	if (kinds[t] != WATER) {
		float b = fbm(p * 0.02 + seed * 2.0) + 0.4 * fbm(p * 0.07);
		vec3 n = normalize(vec3(-dFdx(b) * 9.0, -dFdy(b) * 9.0, 1.0));
		float light = dot(n, normalize(vec3(-0.6, -0.7, 0.8)));
		col *= 0.78 + 0.32 * light;
	}

	// The ledges: slopes facing the light (upper left) lit, the others shaded.
	float ex = slope.x;   // px per tile
	float ey = slope.y;
	float steep = max(abs(ex), abs(ey));
	if (kinds[t] != WATER && kinds[t] != CREVASSE) {
		float shade = clamp(-(ex * 0.45 + ey) / 140.0, -0.4, 0.3);
		col *= 1.0 + shade;
		col *= 0.94 + 0.1 * clamp(h, 0.0, 1.0);   // high ground a little paler, drier
	}

	// Crags: the limestone top and its cliff; cliffs between ledges: bare
	// rock where the ground drops sheer (the mesh's steep rise); scree at the foot.
	float ck = crag_at(p);
	float rk = rock_at(p);
	// A cliff: where the ground climbs cliff_px a tile or more (where the game
	// makes it solid).
	float upright = smoothstep(cliff_px, cliff_px * 1.15, steep) * step(vramp, 0.5);
	if (ck >= 0.7) {
		col = crag_top(p, smoothstep(0.7, 0.85, ck));
	} else if (ck >= rock_solid) {
		col = cliff_face(spos, mix(0.7, 0.95, (ck - rock_solid) / (0.7 - rock_solid)));
	} else if (upright > 0.0 && kinds[t] != WATER && kinds[t] != CREVASSE) {
		// (where the ground stands upright on screen - the mesh stretched up a drop)
		float k = upright;
		vec3 face = cliff_face(spos, 0.9 + clamp(-(ex * 0.45 + ey) / 300.0, -0.25, 0.2));
		col = mix(col, face, k);
	} else if (ck > 0.2) {
		col = mix(col, rock_color.rgb * 0.6, clamp((ck - 0.2) / (rock_solid - 0.2), 0.0, 1.0) * 0.6);   // scree, shadowed
	}

	COLOR = vec4(col, 1.0);
}
