class_name EmpireKit
extends RefCounted
## The empires' looks for ships, stations and their insides, as parts merged
## into one mesh a model (shaders/world/empire.gdshader: each face's zone -
## paint, metal, lamp, screen, leather, cloth, the roundel, the banner, the
## frieze - in its vertex colour). An empire is a material: its colours, its
## emblem (the Minoan triskelion and bull, Athens' owl, Sparta's lambda,
## Mycenae's rosette, Ionia's lyre, the Cyclades' spiral, the Sea Peoples'
## skull) and its frieze - LOOKS, from the reference sheets
## (external/images/<empire>_ships_1.png, _spacestations_1.png).
## A Mesher collects faces (armoured lofts of chamfered sections, lathed
## nacelles, boxes, discs, slabs cut to an outline, flat decals) and commits
## them once; the materials are shared (`mat`: the hull, outside / inside, a
## station's; `glass`; `zone_mat` for other builders' meshes). Builds are
## plain data: worker threads make them.

enum { MAIN, ACCENT, IRON, STEEL, LAMP, SCREEN, ROUNDEL, BANNER, LEATHER, CLOTH, LEAVES, HAZARD, FRIEZE, GOLD, ACCENT2, WOOD }

const SHADER := preload("res://shaders/world/empire.gdshader")
## An empire's look: its colours (main, accent, second accent, iron, steel,
## gold, lamps), its emblem and frieze (the shader's numbers) and their
## colours (ground, ink), how worn its paint is, masonry (blocks) or veined
## marble, the seams' spacing on a ship (m).
const LOOKS := {
	"minoa": {"main": Color(0.80, 0.74, 0.62), "accent": Color(0.46, 0.08, 0.06), "accent2": Color(0.10, 0.36, 0.42), "iron": Color(0.20, 0.20, 0.21),
		"steel": Color(0.62, 0.61, 0.60), "gold": Color(0.83, 0.62, 0.22), "lamp": Color(1.0, 0.58, 0.2), "emblem": 0, "frieze": 0,
		"e_ground": Color(0.46, 0.08, 0.06), "e_ink": Color(0.80, 0.74, 0.62), "f_ground": Color(0.80, 0.74, 0.62), "f_ink": Color(0.46, 0.08, 0.06),
		"wear": 1.0, "blocks": 0.0, "marble": 0.0, "panel": 2.2},
	"athens": {"main": Color(0.86, 0.83, 0.74), "accent": Color(0.07, 0.13, 0.38), "accent2": Color(0.16, 0.30, 0.62), "iron": Color(0.16, 0.18, 0.24),
		"steel": Color(0.70, 0.70, 0.72), "gold": Color(0.86, 0.66, 0.24), "lamp": Color(0.35, 0.85, 1.0), "emblem": 1, "frieze": 1,
		"e_ground": Color(0.88, 0.84, 0.72), "e_ink": Color(0.07, 0.12, 0.32), "f_ground": Color(0.07, 0.13, 0.38), "f_ink": Color(0.9, 0.86, 0.76),
		"wear": 0.5, "blocks": 0.0, "marble": 0.5, "panel": 2.0},
	"sparta": {"main": Color(0.76, 0.66, 0.50), "accent": Color(0.50, 0.06, 0.05), "accent2": Color(0.30, 0.05, 0.04), "iron": Color(0.15, 0.15, 0.16),
		"steel": Color(0.5, 0.5, 0.5), "gold": Color(0.85, 0.62, 0.2), "lamp": Color(1.0, 0.5, 0.12), "emblem": 2, "frieze": 1,
		"e_ground": Color(0.50, 0.06, 0.05), "e_ink": Color(0.88, 0.66, 0.22), "f_ground": Color(0.50, 0.06, 0.05), "f_ink": Color(0.88, 0.66, 0.22),
		"wear": 1.1, "blocks": 0.0, "marble": 0.0, "panel": 2.4},
	"mycenae": {"main": Color(0.56, 0.50, 0.42), "accent": Color(0.50, 0.13, 0.08), "accent2": Color(0.12, 0.2, 0.45), "iron": Color(0.2, 0.18, 0.16),
		"steel": Color(0.55, 0.5, 0.42), "gold": Color(0.9, 0.68, 0.22), "lamp": Color(1.0, 0.6, 0.2), "emblem": 3, "frieze": 3,
		"e_ground": Color(0.50, 0.13, 0.08), "e_ink": Color(0.92, 0.7, 0.24), "f_ground": Color(0.12, 0.2, 0.45), "f_ink": Color(0.92, 0.7, 0.24),
		"wear": 0.8, "blocks": 1.0, "marble": 0.0, "panel": 2.8},
	"ionia": {"main": Color(0.88, 0.85, 0.76), "accent": Color(0.10, 0.20, 0.62), "accent2": Color(0.36, 0.22, 0.6), "iron": Color(0.14, 0.17, 0.26),
		"steel": Color(0.72, 0.72, 0.75), "gold": Color(0.88, 0.7, 0.28), "lamp": Color(0.3, 0.62, 1.0), "emblem": 4, "frieze": 1,
		"e_ground": Color(0.10, 0.20, 0.62), "e_ink": Color(0.9, 0.72, 0.3), "f_ground": Color(0.10, 0.20, 0.62), "f_ink": Color(0.9, 0.86, 0.76),
		"wear": 0.45, "blocks": 0.0, "marble": 0.6, "panel": 2.0},
	"cyclades": {"main": Color(0.90, 0.88, 0.84), "accent": Color(0.14, 0.36, 0.66), "accent2": Color(0.66, 0.27, 0.16), "iron": Color(0.22, 0.25, 0.28),
		"steel": Color(0.75, 0.76, 0.78), "gold": Color(0.75, 0.6, 0.4), "lamp": Color(0.2, 0.95, 0.85), "emblem": 5, "frieze": 4,
		"e_ground": Color(0.92, 0.9, 0.86), "e_ink": Color(0.66, 0.27, 0.16), "f_ground": Color(0.92, 0.9, 0.86), "f_ink": Color(0.14, 0.36, 0.66),
		"wear": 0.3, "blocks": 0.0, "marble": 1.0, "panel": 3.2},
	"pirates": {"main": Color(0.27, 0.27, 0.31), "accent": Color(0.62, 0.08, 0.06), "accent2": Color(0.80, 0.74, 0.60), "iron": Color(0.12, 0.12, 0.14),
		"steel": Color(0.45, 0.45, 0.48), "gold": Color(0.8, 0.72, 0.56), "lamp": Color(1.0, 0.45, 0.1), "emblem": 6, "frieze": 5,
		"e_ground": Color(0.62, 0.08, 0.06), "e_ink": Color(0.85, 0.8, 0.66), "f_ground": Color(0.14, 0.14, 0.16), "f_ink": Color(0.85, 0.8, 0.66),
		"wear": 1.5, "blocks": 0.0, "marble": 0.0, "panel": 1.8},
	"": {"main": Color(0.70, 0.71, 0.73), "accent": Color(0.82, 0.42, 0.12), "accent2": Color(0.2, 0.3, 0.4), "iron": Color(0.2, 0.2, 0.22),
		"steel": Color(0.6, 0.6, 0.62), "gold": Color(0.7, 0.6, 0.4), "lamp": Color(1.0, 0.85, 0.6), "emblem": 7, "frieze": 1,
		"e_ground": Color(0.82, 0.42, 0.12), "e_ink": Color(0.9, 0.9, 0.9), "f_ground": Color(0.2, 0.2, 0.22), "f_ink": Color(0.82, 0.42, 0.12),
		"wear": 1.0, "blocks": 0.0, "marble": 0.0, "panel": 2.2}}
static var _mats := {}


static func look(empire: String) -> Dictionary:
	return LOOKS.get(empire, LOOKS[""])


## An empire's material: "hull" (worn, outside), "inside" (cleaner, no mirror
## metal) or "station" (a station's: plates the size of its scale).
## `base` (a hull's material) able to have a doorway cut in it (the instance's
## cut_lo / cut_hi: a box of its mesh's space not drawn) - only the ships you can
## walk into wear it (the discard costs the others nothing).
static var _cut_shader: Shader
static var _cut_mats := {}


static func cut_mat(base: ShaderMaterial) -> ShaderMaterial:
	if _cut_mats.has(base):
		return _cut_mats[base]
	if _cut_shader == null:
		_cut_shader = Shader.new()
		_cut_shader.code = SHADER.code.replace("shader_type spatial;", "shader_type spatial;\n#define CUTAWAY")
	var m := base.duplicate() as ShaderMaterial
	m.shader = _cut_shader
	_cut_mats[base] = m
	return m


static func mat(kind := "hull", empire := "minoa") -> ShaderMaterial:
	var key := kind + "|" + empire
	if _mats.has(key):
		return _mats[key]
	var L := look(empire)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("noise_tex", Cosmos.noise_ready())
	for k in [["cream", "main"], ["red", "accent"], ["accent2", "accent2"], ["iron", "iron"], ["steel", "steel"], ["gold", "gold"],
			["amber", "lamp"], ["emblem_ground", "e_ground"], ["emblem_ink", "e_ink"], ["frieze_ground", "f_ground"], ["frieze_ink", "f_ink"]]:
		m.set_shader_parameter(k[0], L[k[1]])
	m.set_shader_parameter("emblem", int(L["emblem"]))
	m.set_shader_parameter("frieze", int(L["frieze"]))
	m.set_shader_parameter("wear", float(L["wear"]))
	m.set_shader_parameter("blocks", float(L["blocks"]))
	m.set_shader_parameter("marble", float(L["marble"]))
	m.set_shader_parameter("panel", float(L["panel"]))
	if kind == "inside":
		m.set_shader_parameter("wear", float(L["wear"]) * 0.35)
		m.set_shader_parameter("inside", 1.0)
		m.set_shader_parameter("sway", 0.18)   # (the air stirring the banners)
	elif kind == "station":
		m.set_shader_parameter("panel", float(L["panel"]) * 4.0)
		m.set_shader_parameter("flood", 0.45)
		m.set_shader_parameter("sway", 1.4)
	_mats[key] = m
	return m


## A material that's one zone all over (for meshes without the zone colours).
static func zone_mat(zone: int, kind := "hull", empire := "minoa") -> ShaderMaterial:
	var key := "%s|%s:%d" % [kind, empire, zone]
	if _mats.has(key):
		return _mats[key]
	var m := mat(kind, empire).duplicate() as ShaderMaterial
	m.set_shader_parameter("zone_override", float(zone))
	_mats[key] = m
	return m


## The windows: tinted, glossy, see-through (their outside only: from within you look out).
static func glass() -> StandardMaterial3D:
	if _mats.has("glass"):
		return _mats["glass"]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.25, 0.32, 0.36, 0.28)
	m.metallic = 0.6
	m.roughness = 0.05
	m.cull_mode = BaseMaterial3D.CULL_BACK
	_mats["glass"] = m
	return m


## A soft additive glow (a hologram).
static func holo() -> StandardMaterial3D:
	if _mats.has("holo"):
		return _mats["holo"]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.25, 0.6, 1.0, 0.35)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["holo"] = m
	return m


## Faces gathered for one mesh.
class Mesher:
	var st := SurfaceTool.new()
	var n := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func _c(zone: int, g := 0.0) -> Color:
		return Color(zone / 16.0, g, 0.0, 1.0)

	## A triangle facing away from `inner` (a point inside the part).
	func tri(a: Vector3, b: Vector3, c: Vector3, zone: int, inner: Vector3, uv := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], g := 0.0) -> void:
		var nrm := (b - a).cross(c - a)
		if nrm.length_squared() < 1e-12:
			return
		nrm = nrm.normalized()
		var pts := [a, b, c]
		var uvs: Array = uv
		if nrm.dot((a + b + c) / 3.0 - inner) < 0.0:
			nrm = -nrm
			pts = [a, c, b]
			uvs = [uv[0], uv[2], uv[1]]
		# (Godot's front faces wind clockwise seen from the front)
		var col := _c(zone, g)
		for k in [0, 2, 1]:
			st.set_color(col)
			st.set_normal(nrm)
			st.set_uv(uvs[k])
			st.add_vertex(pts[k])
		n += 1

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, zone: int, inner: Vector3, g := 0.0) -> void:
		var u := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		tri(a, b, c, zone, inner, [u[0], u[1], u[2]], g)
		tri(a, c, d, zone, inner, [u[0], u[2], u[3]], g)

	## A raised plate on a face: the quad a b c d (on the face), lifted `h` off it, its edges closed.
	func plate(a: Vector3, b: Vector3, c: Vector3, d: Vector3, h: float, zone: int, inner: Vector3) -> void:
		var nrm := (b - a).cross(d - a).normalized()
		if nrm.dot((a + c) * 0.5 - inner) < 0.0:
			nrm = -nrm
		var up := nrm * h
		var mid := (a + b + c + d) * 0.25
		quad(a + up, b + up, c + up, d + up, zone, mid - nrm)
		var lo := [a, b, c, d]
		for i in 4:
			var j := (i + 1) % 4
			quad(lo[i], lo[j], lo[j] + up, lo[i] + up, zone, mid + up * 0.5)

	## A box (`size` full) placed by `xf`.
	func box(size: Vector3, xf: Transform3D, zone: int) -> void:
		var h := size * 0.5
		var p := []
		for i in 8:
			p.append(xf * Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
		var o := xf.origin
		for f in [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]:
			quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], zone, o)

	func boxat(size: Vector3, at: Vector3, zone: int, yaw := 0.0) -> void:
		box(size, Transform3D(Basis(Vector3.UP, yaw), at), zone)

	## A flat panel (a decal, a screen, a banner): its middle, half extents along `right` and `down`.
	func panel(mid: Vector3, right: Vector3, down: Vector3, zone: int, facing: Vector3, g := 0.0) -> void:
		var a := mid - right - down
		var b := mid + right - down
		var c := mid + right + down
		var d := mid - right + down
		var inner := mid - facing
		tri(a, b, c, zone, inner, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)], g)
		tri(a, c, d, zone, inner, [Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)], g)

	## A disc (a roundel): UV across it 0..1.
	func disc(mid: Vector3, normal: Vector3, up: Vector3, r: float, zone: int, seg := 32) -> void:
		var right := up.cross(normal).normalized() * r
		var u2 := normal.cross(right).normalized() * r
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var p0 := mid + right * cos(a0) + u2 * sin(a0)
			var p1 := mid + right * cos(a1) + u2 * sin(a1)
			tri(mid, p0, p1, zone, mid - normal, [Vector2(0.5, 0.5), Vector2(0.5 + 0.5 * cos(a0), 0.5 - 0.5 * sin(a0)), Vector2(0.5 + 0.5 * cos(a1), 0.5 - 0.5 * sin(a1))])

	## A cylinder between `a` and `b` (radii ra, rb), `caps` closed.
	func cyl(a: Vector3, b: Vector3, ra: float, rb: float, zone: int, seg := 12, caps := true) -> void:
		if a.distance_squared_to(b) < 1e-8:
			return
		var ax := (b - a).normalized()
		var side := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
		var up := ax.cross(side)
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var d0 := side * cos(a0) + up * sin(a0)
			var d1 := side * cos(a1) + up * sin(a1)
			quad(a + d0 * ra, a + d1 * ra, b + d1 * rb, b + d0 * rb, zone, (a + b) * 0.5)
			if caps:
				tri(a, a + d0 * ra, a + d1 * ra, zone, a + ax)
				tri(b, b + d1 * rb, b + d0 * rb, zone, b - ax)

	## A lathe round the z axis through (x, y): profile [[z, r, zone], ...] - its
	## faces outward on the profile's right (going on in z, away from the axis;
	## a step in at one z faces back, out faces forward).
	func lathe(x: float, y: float, prof: Array, seg := 16) -> void:
		for k in prof.size() - 1:
			var p0: Array = prof[k]
			var p1: Array = prof[k + 1]
			var dz := float(p1[0]) - float(p0[0])
			var dr := float(p1[1]) - float(p0[1])
			var nz := -dr
			var nr := dz
			var c0 := Vector3(x, y, p0[0])
			var c1 := Vector3(x, y, p1[0])
			for i in seg:
				var a0 := TAU * (i + 0.5) / seg
				var a1 := TAU * (i + 1.5) / seg
				var d0 := Vector3(cos(a0), sin(a0), 0)
				var d1 := Vector3(cos(a1), sin(a1), 0)
				var q := [c0 + d0 * p0[1], c0 + d1 * p0[1], c1 + d1 * p1[1], c1 + d0 * p1[1]]
				var mid: Vector3 = (q[0] + q[1] + q[2] + q[3]) * 0.25
				var dm := Vector3(cos(TAU * (i + 1.0) / seg), sin(TAU * (i + 1.0) / seg), 0)
				var out := (dm * nr + Vector3(0, 0, nz)).normalized()
				quad(q[0], q[1], q[2], q[3], int(p1[2]), mid - out * 0.1)

	## An armoured loft through chamfered sections [z, half width, top, bottom, chamfer]:
	## eight faces round (top, chamfers, sides, bottom), `zone_of.call(segment, face)`
	## the zone of each (-1: left out - glass goes in another mesh). `cap_front` closes the first.
	func loft(sections: Array, zone_of: Callable, cap_front := true, cap_back := true) -> void:
		var rings: Array = []
		for s in sections:
			rings.append(ring(s))
		for k in sections.size() - 1:
			var inner := Vector3(0, (float(sections[k][2]) + float(sections[k][3])) * 0.5, (float(sections[k][0]) + float(sections[k + 1][0])) * 0.5)
			for f in 8:
				var z: int = zone_of.call(k, f)
				if z < 0:
					continue
				var j: int = (f + 1) % 8
				quad(rings[k][f], rings[k][j], rings[k + 1][j], rings[k + 1][f], z, inner)
		for e in ([0] if cap_front else []) + ([sections.size() - 1] if cap_back else []):
			var s: Array = sections[e]
			var mid := Vector3(0, (float(s[2]) + float(s[3])) * 0.5, float(s[0]))
			var out := Vector3(0, 0, -1.0 if e == 0 else 1.0)
			for f in 8:
				tri(mid, rings[e][f], rings[e][(f + 1) % 8], IRON if e > 0 else maxi(int(zone_of.call(0, 2)), 0), mid - out)

	## The eight corners of a section (round from the top's left).
	static func ring(s: Array) -> Array:
		var z: float = s[0]
		var w: float = s[1]
		var t: float = s[2]
		var b: float = s[3]
		var c: float = minf(s[4], minf(w, (t - b) * 0.5) * 0.95)
		return [Vector3(-w + c, t, z), Vector3(w - c, t, z), Vector3(w, t - c, z), Vector3(w, b + c, z),
			Vector3(w - c, b, z), Vector3(-w + c, b, z), Vector3(-w, b + c, z), Vector3(-w, t - c, z)]

	## A smooth loft through oval sections [z, half width, half height, y]: `seg` round, capped.
	func round_loft(sections: Array, seg: int, zone_of: Callable) -> void:
		var rings: Array = []
		for s in sections:
			var ring: Array = []
			for i in seg:
				var a := TAU * i / seg
				ring.append(Vector3(cos(a) * float(s[1]), sin(a) * float(s[2]) + float(s[3]), float(s[0])))
			rings.append(ring)
		for k in sections.size() - 1:
			var inner := Vector3(0, (float(sections[k][3]) + float(sections[k + 1][3])) * 0.5, (float(sections[k][0]) + float(sections[k + 1][0])) * 0.5)
			for i in seg:
				var j: int = (i + 1) % seg
				quad(rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i], int(zone_of.call(k, i)), inner)
		for e in [0, sections.size() - 1]:
			var mid := Vector3(0, float(sections[e][3]), float(sections[e][0]))
			for i in seg:
				tri(mid, rings[e][i], rings[e][(i + 1) % seg], int(zone_of.call(mini(e, sections.size() - 2), 0)), mid + Vector3(0, 0, 1.0 if e == 0 else -1.0))

	## A slab cut to an outline (a wing, a fin, a sail): `pts` its outline in
	## the plane (2D), placed by `xf` (the plane's x, y -> xf's x, z; its
	## thickness along xf's y, `t` in all), the faces `zone`, the rim `edge`.
	func slab(pts: PackedVector2Array, xf: Transform3D, t: float, zone: int, edge: int) -> void:
		var idx := Geometry2D.triangulate_polygon(pts)
		var up := xf.basis.y.normalized() * t * 0.5
		var p3: Array = []
		var mid := Vector3.ZERO
		for q in pts:
			var v := xf * Vector3(q.x, 0, q.y)
			p3.append(v)
			mid += v
		mid /= maxf(1.0, pts.size())
		for i in range(0, idx.size(), 3):
			var a: Vector3 = p3[idx[i]]
			var b: Vector3 = p3[idx[i + 1]]
			var c: Vector3 = p3[idx[i + 2]]
			var m3 := (a + b + c) / 3.0
			tri(a + up, b + up, c + up, zone, m3 - up)
			tri(a - up, b - up, c - up, zone, m3 + up)
		for i in pts.size():
			var a: Vector3 = p3[i]
			var b: Vector3 = p3[(i + 1) % pts.size()]
			quad(a - up, b - up, b + up, a + up, edge, mid)

	func commit() -> ArrayMesh:
		return st.commit()

	func arrays() -> Array:
		return st.commit_to_arrays()


## Faces of an armoured loft (`f`): 0 top, 1 upper right, 2 right, 3 lower right,
## 4 bottom, 5 lower left, 6 left, 7 upper left.
const TOP := 0
const SIDES := [2, 6]
const UPPER := [1, 7]
const LOWER := [3, 5]


## A section's numbers at `z` (between the two round it).
static func section_at(sections: Array, z: float) -> Array:
	for k in sections.size() - 1:
		var a: Array = sections[k]
		var b: Array = sections[k + 1]
		if z >= float(a[0]) and z <= float(b[0]):
			var t := (z - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			return [z, lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), lerpf(a[3], b[3], t), lerpf(a[4], b[4], t)]
	return sections[0] if z < float(sections[0][0]) else sections[sections.size() - 1]


## A crate's own mesh (1.2 x 0.88 x 1.3 m, its foot at the origin), plain or
## in the accent: made once - a hold's cargo is instances of the two.
static var _crate_meshes := {}


static func crate_mesh(red: bool) -> ArrayMesh:
	if not _crate_meshes.has(red):
		var m := Mesher.new()
		crate(m, Vector3.ZERO, Vector3(1.2, 0.88, 1.3), red)
		_crate_meshes[red] = m.commit()
	return _crate_meshes[red]


## A crate of an empire's stores: steel-cornered, in its main colour or its accent, its emblem on the sides.
static func crate(m: Mesher, at: Vector3, size: Vector3, red := false, yaw := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	var xf := Transform3D(b, at + Vector3(0, size.y * 0.5, 0))
	m.box(size, xf, ACCENT if red else MAIN)
	# (steel edges)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			m.box(Vector3(0.08, size.y + 0.02, 0.08), Transform3D(b, xf * Vector3(sx * size.x * 0.5, 0, sz * size.z * 0.5)), STEEL)
	var r := minf(size.y, size.z) * 0.32
	for sx in [-1.0, 1.0]:
		var nrm := b * Vector3(sx, 0, 0)
		m.disc(xf * Vector3(sx * (size.x * 0.5 + 0.012), 0, 0), nrm, Vector3.UP, r, ROUNDEL, 20)
