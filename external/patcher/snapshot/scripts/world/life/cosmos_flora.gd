class_name CosmosFlora
extends RefCounted
## A planet's plants in the 3D game (stage 3): a handful of species designed
## from the planet's seed and type - trees (round-crowned or spired), bushes,
## grass, crystals, fungi, cacti - each its own small mesh built here (vertex
## colours from the planet's palette, an alien hue now and then), and the
## rules for where it grows (heights, slopes, how thick). CosmosPlanet builds
## the designs on a worker at its setup and scatters them on its finest
## patches (MultiMeshes - one draw a species a patch); they sway in the wind
## (flora.gdshader). Thread-safe: designs are plain data (mesh arrays).
##   var species := CosmosFlora.design(shape, seed)   # [{kind, arrays, ...}]

const KINDS_BY_TYPE := {
	"ocean": ["tree", "bush", "grass", "flower"],
	"ice": ["spire", "crystal", "grass"],
	"volcanic": ["crystal", "fungus", "cactus"],
	"moon": ["crystal"],
	"rocky": ["cactus", "fungus", "grass"],
}


## The species of a planet (its PlanetShape and seed).
static func design(shape: PlanetShape, seed: int, type: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 31 + 7
	var kinds: Array = KINDS_BY_TYPE.get(type, KINDS_BY_TYPE["rocky"])
	var L := shape.look
	var leaf: Color = L.get("land_mid", Color(0.3, 0.5, 0.3))
	var alt: Color = L.get("biome_color", leaf)
	var out: Array = []
	for i in kinds.size():
		var kind: String = kinds[i]
		var c1 := leaf.lerp(alt, rng.randf() * 0.6)
		if rng.randf() < 0.25:
			c1 = Color.from_hsv(rng.randf(), rng.randf_range(0.4, 0.8), rng.randf_range(0.4, 0.8))   # (an alien hue)
		c1 = c1.lightened(rng.randf_range(-0.1, 0.15))
		if L.has("flora"):   # (the empire's land: PlanetShape._empire_tint)
			c1 = c1.lerp(L["flora"], float(L.get("flora_k", 0.0)))
		var sp := {"kind": kind, "color": c1, "density": 1.0, "min_h": 0.05, "max_h": 1.6, "max_slope": 0.35,
			"size": Vector2(0.8, 1.3), "solid": 0.0, "glow": 0.0}
		match kind:
			"tree":
				sp["arrays"] = _tree(rng, c1, Color(0.35, 0.24, 0.16).lerp(c1, 0.15))
				sp["density"] = rng.randf_range(0.25, 0.9)
				sp["size"] = Vector2(0.7, 1.5)
				sp["solid"] = 0.45
			"spire":
				sp["arrays"] = _spire(rng, c1.darkened(0.2), Color(0.3, 0.22, 0.16))
				sp["density"] = rng.randf_range(0.25, 0.8)
				sp["size"] = Vector2(0.7, 1.4)
				sp["solid"] = 0.35
			"bush":
				sp["arrays"] = _blob(rng, c1.darkened(0.1), 0.9, 0.7)
				sp["density"] = rng.randf_range(1.0, 3.0)
				sp["size"] = Vector2(0.5, 1.4)
			"grass":
				sp["arrays"] = _grass(rng, c1.lightened(0.05))
				sp["density"] = rng.randf_range(12.0, 22.0)
				sp["size"] = Vector2(0.7, 1.3)
				sp["max_slope"] = 0.45
			"flower":
				sp["arrays"] = _flower(rng, Color.from_hsv(rng.randf(), 0.7, 0.95), c1)
				sp["density"] = rng.randf_range(2.0, 6.0)
				sp["size"] = Vector2(0.7, 1.2)
			"crystal":
				var cc := Color.from_hsv(rng.randf(), rng.randf_range(0.5, 0.9), 0.95)
				if type == "volcanic":
					cc = (L.get("lava_color", Color(1.0, 0.4, 0.1)) as Color)
				sp["arrays"] = _crystal(rng, cc)
				sp["density"] = rng.randf_range(0.4, 1.5)
				sp["size"] = Vector2(0.5, 2.0)
				sp["glow"] = 1.6
				sp["min_h"] = -0.2
				sp["max_slope"] = 0.7
				sp["solid"] = 0.3
			"fungus":
				sp["arrays"] = _fungus(rng, Color.from_hsv(rng.randf(), 0.6, 0.85), Color(0.85, 0.8, 0.7))
				sp["density"] = rng.randf_range(0.8, 3.0)
				sp["size"] = Vector2(0.6, 2.2)
				sp["glow"] = 0.6 if rng.randf() < 0.5 else 0.0
				sp["min_h"] = -0.3
			"cactus":
				sp["arrays"] = _cactus(rng, c1.darkened(0.15))
				sp["density"] = rng.randf_range(0.4, 1.4)
				sp["size"] = Vector2(0.7, 1.5)
				sp["solid"] = 0.35
		out.append(sp)
	return out


# --- Meshes (unit-ish, standing on y = 0) -----------------------------------------

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _end(st: SurfaceTool) -> Array:
	st.generate_normals()
	return st.commit_to_arrays()


## One triangle, wound so its front faces `out` (Godot's front faces wind
## clockwise: their normal is (c - a) x (b - a)).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3, cols: Array, glow: float) -> void:
	var pts := [a, b, c]
	var order := [0, 1, 2] if (c - a).cross(b - a).dot(out) >= 0.0 else [0, 2, 1]
	for k in order:
		st.set_color(cols[k])
		st.set_uv(Vector2(glow, (pts[k] as Vector3).y))
		st.add_vertex(pts[k])


## A tapered tube from `a` to `b`, radii ra -> rb, n sides.
static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, n: int, col: Color, glow := 0.0) -> void:
	var ax := (b - a).normalized()
	var p := ax.cross(Vector3.RIGHT if absf(ax.x) < 0.9 else Vector3.FORWARD).normalized()
	var q := ax.cross(p)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := p * cos(a0) + q * sin(a0)
		var d1 := p * cos(a1) + q * sin(a1)
		var v := [a + d0 * ra, b + d0 * rb, b + d1 * rb, a + d1 * ra]
		var out := (d0 + d1).normalized()
		_tri(st, v[0], v[1], v[2], out, [col, col, col], glow)
		_tri(st, v[0], v[2], v[3], out, [col, col, col], glow)


## A lumpy ball (an icosphere-ish sphere pushed about), centre `c`, radii `r`.
static func _lump(st: SurfaceTool, rng: RandomNumberGenerator, c: Vector3, r: Vector3, col: Color, glow := 0.0, seg := 7) -> void:
	var bumps := [rng.randf() * TAU, rng.randf() * TAU, rng.randf_range(0.1, 0.25)]
	var pts := []
	for j in seg + 1:
		var row := []
		var th := PI * j / seg
		for i in seg * 2:
			var ph := TAU * i / (seg * 2)
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var k: float = 1.0 + bumps[2] * sin(ph * 3.0 + bumps[0]) * sin(th * 2.0 + bumps[1])
			row.append(c + d * r * k)
		pts.append(row)
	for j in seg:
		for i in seg * 2:
			var i2 := (i + 1) % (seg * 2)
			var v := [pts[j][i], pts[j][i2], pts[j + 1][i2], pts[j + 1][i]]
			var shade := 0.8 + 0.25 * (1.0 - float(j) / seg)
			var cc := col * Color(shade, shade, shade)
			var out: Vector3 = (v[0] + v[2]) * 0.5 - c
			_tri(st, v[0], v[1], v[2], out, [cc, cc, cc], glow)
			_tri(st, v[0], v[2], v[3], out, [cc, cc, cc], glow)


static func _tree(rng: RandomNumberGenerator, leaf: Color, bark: Color) -> Array:
	var st := _begin()
	var h := rng.randf_range(4.0, 8.0)
	var bend := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
	_tube(st, Vector3.ZERO, Vector3(0, h * 0.55, 0) + bend * 0.5, 0.35, 0.22, 6, bark)
	_tube(st, Vector3(0, h * 0.55, 0) + bend * 0.5, Vector3(0, h * 0.85, 0) + bend, 0.22, 0.12, 6, bark)
	var crowns := rng.randi_range(2, 5)
	for i in crowns:
		var r := rng.randf_range(1.2, 2.2) * h / 6.0
		var at := Vector3(rng.randf_range(-1.2, 1.2), h * rng.randf_range(0.65, 0.95), rng.randf_range(-1.2, 1.2)) + bend
		_lump(st, rng, at, Vector3(r, r * rng.randf_range(0.7, 1.0), r), leaf.lightened(rng.randf_range(-0.12, 0.12)))
	return _end(st)


static func _spire(rng: RandomNumberGenerator, leaf: Color, bark: Color) -> Array:
	# A conifer: stacked cones round a trunk.
	var st := _begin()
	var h := rng.randf_range(5.0, 10.0)
	_tube(st, Vector3.ZERO, Vector3(0, h * 0.3, 0), 0.3, 0.25, 6, bark)
	var tiers := rng.randi_range(3, 5)
	for i in tiers:
		var y := h * (0.2 + 0.75 * float(i) / tiers)
		var r := (1.0 - float(i) / tiers) * h * 0.28 + 0.3
		_tube(st, Vector3(0, y, 0), Vector3(0, y + h * 0.32, 0), r, 0.05, 8, leaf.lightened(0.05 * i))
	return _end(st)


static func _blob(rng: RandomNumberGenerator, col: Color, w: float, hh: float) -> Array:
	var st := _begin()
	for i in rng.randi_range(2, 4):
		var r := rng.randf_range(0.4, 0.75) * w
		_lump(st, rng, Vector3(rng.randf_range(-0.5, 0.5), r * hh, rng.randf_range(-0.5, 0.5)), Vector3(r, r * hh, r), col.lightened(rng.randf_range(-0.1, 0.1)), 0.0, 5)
	return _end(st)


static func _grass(rng: RandomNumberGenerator, col: Color) -> Array:
	# A tuft of blades, each a thin bent triangle (both sides).
	var st := _begin()
	for i in rng.randi_range(6, 11):
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.25)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.1, 0.35)
		var h := rng.randf_range(0.35, 0.8)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.05
		var tip := base + lean + Vector3(0, h, 0)
		var c := col.lightened(rng.randf_range(-0.12, 0.12))
		for tri in [[base - side, tip, base + side], [base + side, tip, base - side]]:
			for v in tri:
				st.set_color(c * Color(0.7, 0.7, 0.7) if v != tip else c)
				st.set_uv(Vector2(0.0, (v as Vector3).y))
				st.add_vertex(v)
	return _end(st)


static func _flower(rng: RandomNumberGenerator, petal: Color, stem: Color) -> Array:
	var st := _begin()
	for i in rng.randi_range(2, 5):
		var at := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		var h := rng.randf_range(0.3, 0.7)
		_tube(st, at, at + Vector3(0, h, 0), 0.025, 0.02, 4, stem)
		_lump(st, rng, at + Vector3(0, h, 0), Vector3(0.12, 0.06, 0.12), petal, 0.15, 4)
	return _end(st)


static func _crystal(rng: RandomNumberGenerator, col: Color) -> Array:
	var st := _begin()
	for i in rng.randi_range(3, 7):
		var dir := Vector3(rng.randf_range(-0.5, 0.5), 1.0, rng.randf_range(-0.5, 0.5)).normalized()
		var h := rng.randf_range(0.5, 1.6)
		var r := rng.randf_range(0.08, 0.22)
		var base := Vector3(rng.randf_range(-0.25, 0.25), -0.1, rng.randf_range(-0.25, 0.25))
		var c := col.lightened(rng.randf_range(-0.15, 0.2))
		_tube(st, base, base + dir * h, r, r, 6, c, 1.0)
		_tube(st, base + dir * h, base + dir * (h + r * 2.2), r, 0.0, 6, c.lightened(0.2), 1.0)
	return _end(st)


static func _fungus(rng: RandomNumberGenerator, cap: Color, stem: Color) -> Array:
	var st := _begin()
	for i in rng.randi_range(1, 4):
		var at := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
		var h := rng.randf_range(0.4, 1.6)
		var r := rng.randf_range(0.3, 0.8) * h
		_tube(st, at, at + Vector3(0, h, 0), r * 0.2, r * 0.15, 6, stem)
		_lump(st, rng, at + Vector3(0, h, 0), Vector3(r, r * 0.45, r), cap.lightened(rng.randf_range(-0.1, 0.1)), 0.5, 6)
	return _end(st)


static func _cactus(rng: RandomNumberGenerator, col: Color) -> Array:
	var st := _begin()
	var h := rng.randf_range(1.5, 3.5)
	_tube(st, Vector3.ZERO, Vector3(0, h, 0), 0.3, 0.26, 8, col)
	_lump(st, rng, Vector3(0, h, 0), Vector3(0.26, 0.2, 0.26), col, 0.0, 4)
	for i in rng.randi_range(0, 3):
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var y := h * rng.randf_range(0.3, 0.6)
		var elbow := Vector3(0, y, 0) + d * 0.7
		_tube(st, Vector3(0, y, 0), elbow, 0.16, 0.16, 6, col)
		_tube(st, elbow, elbow + Vector3(0, rng.randf_range(0.5, 1.0), 0), 0.16, 0.13, 6, col)
	return _end(st)


## Where a species grows: `h` metres above the sea (or the radius), `slope`
## 0 flat .. 1 sheer, `snow` true over the snow line.
static func grows(sp: Dictionary, shape: PlanetShape, h: float, slope: float) -> bool:
	var hn := h / maxf(shape.amp, 1.0)
	if hn < float(sp["min_h"]) or hn > float(sp["max_h"]) or slope > float(sp["max_slope"]):
		return false
	if shape.sea > 0 and h < 0.6 and sp["kind"] != "crystal":
		return false
	return true
