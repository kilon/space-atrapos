class_name MapKit
extends RefCounted
## The 3D maps' parts (the Automaton's planet, solar and galaxy maps -
## Map3DView): their few shaders (shaders/maps/: lines, worlds, glows, the
## reference plane, points, the planet map's globe) as shared materials, and the meshes made of them - lines as
## screen-wide ribbons (Lines), soft glows by the hundred in one MultiMesh,
## point clouds, one shared sphere. Every material is one of six shaders
## (CosmosWarm draws each at the title: no compile hitch the first time a map
## opens).

const LINE := preload("res://shaders/maps/map_line.gdshader")
const BODY := preload("res://shaders/maps/map_body.gdshader")
const GLOW := preload("res://shaders/maps/map_glow.gdshader")
const PLANE := preload("res://shaders/maps/map_plane.gdshader")
const POINTS := preload("res://shaders/maps/map_points.gdshader")
const GLOBE := preload("res://shaders/maps/map_globe.gdshader")

static var _line_mat: ShaderMaterial
static var _glow_mat: ShaderMaterial
static var _points_mat: ShaderMaterial
static var _sphere: SphereMesh
static var _quad: QuadMesh


## The lines' material (one for every line of every map: colours, widths and
## dashes are the vertices').
static func line_material() -> ShaderMaterial:
	if _line_mat == null:
		_line_mat = ShaderMaterial.new()
		_line_mat.shader = LINE
		_line_mat.render_priority = 1   # (over the plane's haze)
	return _line_mat


static func glow_material() -> ShaderMaterial:
	if _glow_mat == null:
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = GLOW
		_glow_mat.render_priority = 2
	return _glow_mat


static func points_material(size_px := 2.0) -> ShaderMaterial:
	if _points_mat == null:
		_points_mat = ShaderMaterial.new()
		_points_mat.shader = POINTS
	if is_equal_approx(size_px, 2.0):
		return _points_mat
	var m := _points_mat.duplicate() as ShaderMaterial
	m.set_shader_parameter("size_px", size_px)
	return m


## A world's (or star's) material - its own (its colours are parameters).
static func body_material(look: Dictionary, star := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BODY
	set_look(m, look, star)
	return m


## A world's look (PlanetGen's colours) as the body shader's parameters.
static func set_look(m: ShaderMaterial, L: Dictionary, star := false) -> void:
	if star:
		m.set_shader_parameter("emit", 1.0)
		m.set_shader_parameter("c_low", L.get("c_dark", Color(0.6, 0.3, 0.05)))
		m.set_shader_parameter("c_mid", L.get("c_mid", Color(1.0, 0.75, 0.35)))
		m.set_shader_parameter("c_high", L.get("c_hot", Color(1.0, 0.95, 0.8)))
		return
	var gas := int(L.get("mode", 0)) == 1 or L.has("gas_a")
	m.set_shader_parameter("bands", 1.0 if gas else 0.0)
	if gas:
		m.set_shader_parameter("c_low", L.get("gas_a", L.get("color_dark", Color(0.5, 0.4, 0.3))))
		m.set_shader_parameter("c_mid", L.get("gas_b", L.get("color_light", Color(0.8, 0.7, 0.5))))
		m.set_shader_parameter("c_high", L.get("gas_c", Color(0.9, 0.85, 0.75)))
	else:
		var wet := L.has("water_deep")
		m.set_shader_parameter("c_low", L.get("water_deep", L.get("land_low", L.get("color_dark", Color(0.3, 0.3, 0.3)))))
		m.set_shader_parameter("c_mid", L.get("land_mid", L.get("color_light", Color(0.5, 0.5, 0.5))))
		m.set_shader_parameter("c_high", L.get("ice_color", L.get("land_high", Color(0.8, 0.8, 0.8))))
		m.set_shader_parameter("sea", clampf(float(L.get("water_level", 0.5)), 0.2, 0.7) if wet else 0.28)
	m.set_shader_parameter("c_air", L.get("atmosphere", Color(0.5, 0.7, 1.0)))
	m.set_shader_parameter("air", clampf(float(L.get("atmo_strength", 0.5)) * 1.2, 0.15, 0.9))
	m.set_shader_parameter("seed", float(int(L.get("seed", 0)) % 97))


## The reference plane's material (its own: grid colour, fog).
static func plane_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PLANE
	m.set_shader_parameter("grid_col", NeonTheme.HEAD)
	m.set_shader_parameter("haze_col", Color(0.0, 0.0, 0.0))
	return m


## The planet map's globe material (its own: its fog texture).
static func globe_material(fog: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOBE
	m.set_shader_parameter("grid_col", NeonTheme.HEAD)
	if fog:
		m.set_shader_parameter("fog_tex", fog)
	else:
		m.set_shader_parameter("has_fog", 0.0)
	return m


## The one sphere every world on the maps is (scaled).
static func sphere() -> SphereMesh:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 48
		_sphere.rings = 24
	return _sphere


static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


## A MultiMesh of `n` glows (set each with set_glow).
static func glows(n: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad()
	mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = glow_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0   # (its quads are turned and sized in the shader)
	return mi


## One glow: at `at`, `size` across in the world but at least `min_px` on the
## screen, its core `core` bright.
static func set_glow(mi: MultiMeshInstance3D, i: int, at: Vector3, size: float, col: Color, min_px := 10.0, core := 0.6) -> void:
	mi.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), at))
	mi.multimesh.set_instance_color(i, col)
	mi.multimesh.set_instance_custom_data(i, Color(min_px, core, 0.0, 0.0))


## Ring kinds (the glow shader's): a marker's ring, one that pulses, an arc turning round.
const RING := 1.0
const PULSE := 2.0
const TURNING := 3.0

## One ring: `px` across on the screen (or `size` in the world, if bigger),
## `thick` px thick.
static func set_ring(mi: MultiMeshInstance3D, i: int, at: Vector3, px: float, col: Color, kind := RING, thick := 1.6, size := 0.0) -> void:
	mi.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * maxf(size, 0.0001)), at))
	mi.multimesh.set_instance_color(i, col)
	mi.multimesh.set_instance_custom_data(i, Color(px, 0.0, kind, thick))


## A cloud of points (stars far off, an asteroid field's rocks): sizes as
## multiples of the material's size_px.
static func points(pts: PackedVector3Array, cols: PackedColorArray, sizes: PackedFloat32Array) -> ArrayMesh:
	var uv := PackedVector2Array()
	uv.resize(pts.size())
	for i in pts.size():
		uv[i] = Vector2(sizes[i] if i < sizes.size() else 1.0, 0.0)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uv
	var m := ArrayMesh.new()
	if not pts.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arr)
	return m


## Lines to draw (segments, polylines, circles), made into one mesh: each
## segment a quad the line shader turns to the camera and widens to its
## width in pixels. Colours, widths and dashes per segment.
class Lines:
	var verts := PackedVector3Array()
	var other := PackedFloat32Array()     # (CUSTOM0: the other end, and the side)
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	func is_empty() -> bool:
		return verts.is_empty()

	## A segment a-b, `width` px; `dash`: dashes along it (0: solid) flowing
	## at `flow` dashes a second; `col_b`: its colour at b (a fade).
	func seg(a: Vector3, b: Vector3, col: Color, width := 2.0, dash := 0.0, flow := 0.0, col_b: Variant = null) -> void:
		var cb: Color = col if col_b == null else col_b
		var n := verts.size()
		for e in [[a, b, col, 0.0], [b, a, cb, 1.0]]:
			for side in [1.0, -1.0]:
				verts.append(e[0])
				var off: float = side if e[3] == 0.0 else -side   # (seen from b the line runs back: its sides swap)
				other.append_array([e[1].x, e[1].y, e[1].z, off])
				uv.append(Vector2(e[3] * dash, width * side))
				uv2.append(Vector2(1.0 if dash > 0.0 else 0.0, flow))
				cols.append(e[2])
		idx.append_array([n, n + 1, n + 2, n + 1, n + 3, n + 2])

	## Through `pts` in turn (closed: back to the first).
	func poly(pts: PackedVector3Array, col: Color, width := 2.0, closed := false, dash := 0.0) -> void:
		var m := pts.size() if closed else pts.size() - 1
		for i in m:
			seg(pts[i], pts[(i + 1) % pts.size()], col, width, dash)

	## A circle round `c` of radius r in the plane of `u` and `v` (unit axes).
	func circle(c: Vector3, r: float, col: Color, width := 1.5, n := 96, u := Vector3.RIGHT, v := Vector3.BACK) -> void:
		var pts := PackedVector3Array()
		for i in n:
			var a := TAU * i / n
			pts.append(c + (u * cos(a) + v * sin(a)) * r)
		poly(pts, col, width, true)

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		if verts.is_empty():
			return m
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_CUSTOM0] = other
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {},
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		return m

	## Into `mi` (made if null), with the lines' material.
	func into(mi: MeshInstance3D) -> MeshInstance3D:
		if mi == null:
			mi = MeshInstance3D.new()
			mi.material_override = MapKit.line_material()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 16384.0   # (widened in the shader)
		mi.mesh = mesh()
		return mi
