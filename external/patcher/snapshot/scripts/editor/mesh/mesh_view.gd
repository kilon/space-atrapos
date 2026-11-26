extends SubViewportContainer
## The mesh editor's 3D view: a world of its own (a studio sky, a key, fill and
## rim light, so physically based materials look as they will in the game), a
## floor grid with the X (red) and Z (blue) axes, an orbiting camera, and the
## edit-mode overlays - the wireframe, the points, the selected edges and
## faces - each one mesh (lines / points / triangles) refilled from the edit
## mesh's arrays, never a node a vertex. Drawn on top in 2D: the box being
## dragged, the proportional-editing circle and the transform's hint.
## Renders only when something changed (request()): an idle editor costs no GPU.

const OVERLAY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float bias = 0.0015;
uniform float psize = 7.0;
uniform bool use_vc = false;
void vertex() {
	// Lifted towards the camera, over the surface: in view space - in perspective along its
	// own ray (the same spot on screen, a little nearer), in an orthographic view straight
	// forward - `bias` a share of its distance (perspective) or metres x 100 (orthographic).
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (PROJECTION_MATRIX[3][3] == 0.0) {
		v.xyz *= 1.0 - bias * 4.0;
	} else {
		v.z += bias * 10.0;
	}
	POSITION = PROJECTION_MATRIX * v;
	//POINTS
}
void fragment() {
	vec4 c = use_vc ? COLOR * tint : tint;
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
"""
const SEL := Color(1.0, 0.42, 0.0)   # (the selection: a strong, saturated orange)
const WIRE := Color(0.06, 0.07, 0.1, 0.9)   # (dark lines over the model; their pale x-ray beneath)
const POINT := Color(0.08, 0.08, 0.1)

var sv: SubViewport
var cam: Camera3D
var world: Node3D             # what's edited goes in here
var target := Vector3(0, 0.9, 0)
var yaw := 0.6
var pitch := -0.35
var dist := 4.0
var ortho := false
## 2D overlay: the box being dragged (size 0: none), the influence circle (radius 0: none), a hint.
var box := Rect2()
var circle_at := Vector2.ZERO
var circle_r := 0.0
var hint := ""

var wire_mi: MeshInstance3D
var pts_mi: MeshInstance3D
var sel_edges_mi: MeshInstance3D
var sel_faces_mi: MeshInstance3D
var _shader: Shader
var _xray: Shader
var _points_shader: Shader
var wire_back_mi: MeshInstance3D
var wire_all_mi: MeshInstance3D
var sel_pts_mi: MeshInstance3D
var _sel_through: Array = []
var _key: DirectionalLight3D
var _off := false
## Edit mode shows every triangle's edges (true), or the faces' (n-gons: their diagonals left out).
var show_tris := false
## The knife's cut being drawn (mesh_editor.gd fills it): its points (global), how each
## snapped (0 a point, 1 an edge, 2 the face), the spot under the mouse it would take
## next (Vector3.INF: none - then `knife_mouse`), and whether it cuts right through.
var knife_on := false
var knife_pts := PackedVector3Array()
var knife_kinds := PackedInt32Array()
var knife_next := Vector3.INF
var knife_next_kind := 2
var knife_mouse := Vector2(-1, -1)
var knife_through := false
const KNIFE := Color(0.35, 1.0, 0.8)
## Auto select: what a click would pick, drawn faintly (-1: nothing; 0 a point, 1 an edge,
## 2 a face - its triangles' corners, three by three), global.
var pre_kind := -1
var pre_pts := PackedVector3Array()


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	sv = SubViewport.new()
	sv.gui_disable_input = true   # (nothing to click inside it: the view takes the input - and what's dragged in from the panels is dropped on the view, not lost inside)
	# (over a view of a scene Godot leaves the cursor to the scene inside - which takes no input here, so a
	# panel divider's resize arrows stayed on over the view after the mouse left the divider: the arrow put
	# back as the mouse comes in and moves over it)
	hook_cursor()
	sv.own_world_3d = true
	sv.world_3d = World3D.new()
	sv.msaa_3d = Viewport.MSAA_4X
	sv.positional_shadow_atlas_size = 0
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sv)
	sv.size_changed.connect(request)
	_build_world()


func _build_world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.16, 0.18, 0.24)
	sm.sky_horizon_color = Color(0.42, 0.40, 0.38)
	sm.ground_bottom_color = Color(0.05, 0.05, 0.06)
	sm.ground_horizon_color = Color(0.3, 0.28, 0.26)
	sm.sun_angle_max = 30.0
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.075, 0.08, 0.1)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)
	_key = DirectionalLight3D.new()
	_key.rotation_degrees = Vector3(-48, -35, 0)
	_key.light_energy = 1.6
	_key.light_color = Color(1.0, 0.95, 0.88)
	_key.shadow_enabled = true
	_key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_key.directional_shadow_max_distance = 30.0
	sv.add_child(_key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.75, 0.85, 1.0)
	sv.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 200, 0)
	rim.light_energy = 0.6
	sv.add_child(rim)
	cam = Camera3D.new()
	cam.near = 0.01
	cam.far = 500.0
	cam.fov = 40.0
	sv.add_child(cam)
	world = Node3D.new()
	world.name = "World"
	sv.add_child(world)
	_shader = Shader.new()
	_shader.code = OVERLAY_SHADER
	# (the points' own: a point size set draws lines and triangles as dots at their corners)
	_points_shader = Shader.new()
	_points_shader.code = OVERLAY_SHADER.replace("//POINTS", "POINT_SIZE = psize;")
	sv.add_child(_grid())
	# The hovered area's wireframe on top of the surface (lifted well clear of it), and again
	# faintly through it (its edges behind a bulge still show).
	wire_all_mi = _overlay(Color(WIRE, 0.6), 0.005, false, 1)   # (the whole wireframe, faint: always, in edit mode)
	wire_mi = _overlay(WIRE, 0.006, true, 2)   # (its vertex colours: the hovered area fading out)
	_xray = Shader.new()
	_xray.code = OVERLAY_SHADER.replace("depth_draw_never,", "depth_draw_never, depth_test_disabled,")
	wire_back_mi = MeshInstance3D.new()
	wire_back_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wire_back_mi.mesh = wire_mi.mesh
	var xm := material(Color(0.9, 0.95, 1.0, 0.22), 0.0, true)
	xm.shader = _xray
	xm.render_priority = 0
	wire_back_mi.material_override = xm
	wire_back_mi.visible = false
	sv.add_child(wire_back_mi)
	sel_edges_mi = _overlay(SEL, 0.007, false, 2)
	sel_faces_mi = _overlay(Color(SEL, 0.55), 0.003, false, 0)
	# (the selection seen through the model too, fainter: what's selected behind a bulge)
	for src in [[sel_edges_mi, 0.5], [sel_faces_mi, 0.18]]:
		var through := MeshInstance3D.new()
		through.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		through.mesh = (src[0] as MeshInstance3D).mesh
		var tm := material(Color(SEL, src[1]), 0.0, false)
		tm.shader = _xray
		through.material_override = tm
		through.visible = false
		sv.add_child(through)
		_sel_through.append(through)
	pts_mi = _overlay(Color.WHITE, 0.008, true, 3)
	(pts_mi.material_override as ShaderMaterial).shader = _points_shader
	(pts_mi.material_override as ShaderMaterial).set_shader_parameter("psize", 3.5)   # (the points: small dots)
	sel_pts_mi = _overlay(SEL, 0.009, false, 4)   # (the selected points: bigger, on top)
	(sel_pts_mi.material_override as ShaderMaterial).shader = _points_shader
	(sel_pts_mi.material_override as ShaderMaterial).set_shader_parameter("psize", 7.0)
	update_camera()


func _overlay(tint: Color, bias: float, vc: bool, prio: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.mesh = ArrayMesh.new()
	var m := material(tint, bias, vc)
	m.render_priority = prio
	mi.material_override = m
	mi.visible = false
	sv.add_child(mi)
	return mi


func material(tint: Color, bias := 0.0, vc := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("bias", bias)
	m.set_shader_parameter("use_vc", vc)
	return m


func _grid() -> MeshInstance3D:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var n := 20
	var step := 0.5
	for i in range(-n, n + 1):
		var x := i * step
		var col := Color(1, 1, 1, 0.16 if i % 2 == 0 else 0.07)
		if i == 0:
			v.append_array([Vector3(-n * step, 0, 0), Vector3(n * step, 0, 0)])
			c.append_array([Color(0.95, 0.3, 0.3, 0.8), Color(0.95, 0.3, 0.3, 0.8)])   # X
			v.append_array([Vector3(0, 0, -n * step), Vector3(0, 0, n * step)])
			c.append_array([Color(0.3, 0.5, 1.0, 0.8), Color(0.3, 0.5, 1.0, 0.8)])     # Z
			continue
		v.append_array([Vector3(x, 0, -n * step), Vector3(x, 0, n * step), Vector3(-n * step, 0, x), Vector3(n * step, 0, x)])
		c.append_array([col, col, col, col])
	# the Y axis, short
	v.append_array([Vector3.ZERO, Vector3(0, 0.6, 0)])
	c.append_array([Color(0.4, 0.9, 0.4, 0.8), Color(0.4, 0.9, 0.4, 0.8)])
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_COLOR] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, a)
	var mi := MeshInstance3D.new()
	mi.name = "Grid"
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = material(Color.WHITE, 0.0, true)
	return mi


## Draw a frame (the scene changed).
func request() -> void:
	if not _off and sv:
		sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


## Rendering off while Talos shows another tool (the host parks it off screen).
func set_off(off: bool) -> void:
	_off = off
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED if off else SubViewport.UPDATE_ONCE


# --- the camera -----------------------------------------------------------------

## The arrow put back over the view (see _init) - connected once; the editor calls it each frame, so a
## view made before this was live-reloaded in gets it too.
func hook_cursor() -> void:
	if not mouse_entered.is_connected(_plain_cursor):
		mouse_entered.connect(_plain_cursor)
	if not gui_input.is_connected(_cursor_input):
		gui_input.connect(_cursor_input)


func _cursor_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_plain_cursor()


func _plain_cursor() -> void:
	if DisplayServer.cursor_get_shape() != DisplayServer.CURSOR_ARROW:
		DisplayServer.cursor_set_shape(DisplayServer.CURSOR_ARROW)


func update_camera() -> void:
	pitch = clampf(pitch, -1.55, 1.55)
	dist = clampf(dist, 0.05, 300.0)
	var b := Basis.from_euler(Vector3(pitch, yaw, 0))
	cam.transform = Transform3D(b, target + b.z * dist)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL if ortho else Camera3D.PROJECTION_PERSPECTIVE
	cam.size = dist * 0.75
	cam.near = maxf(0.005, dist * 0.005) if not ortho else 0.01
	cam.far = maxf(100.0, dist * 50.0)
	if ortho:
		cam.transform.origin = target + b.z * maxf(dist, 50.0)
	request()


## The view turned by a mouse drag `rel`: about its target, or - `pivot` given - about that
## point (edit mode: the selection), which stays where it is on screen while the camera
## goes round it.
func orbit(rel: Vector2, pivot := Vector3.INF) -> void:
	var b0 := Basis.from_euler(Vector3(pitch, yaw, 0))
	yaw -= rel.x * 0.008
	pitch = clampf(pitch - rel.y * 0.008, -1.55, 1.55)
	if pivot == Vector3.INF:
		update_camera()
		return
	var b1 := Basis.from_euler(Vector3(pitch, yaw, 0))
	var r := b1 * b0.inverse()
	var c0 := target + b0.z * dist   # (the camera, as update_camera places it)
	var c1 := pivot + r * (c0 - pivot)
	target = c1 - b1.z * dist   # (the target kept on the view's axis, as far as it was)
	update_camera()


## The view slid by a mouse move `rel` (right drag, Shift + middle drag): what was under the mouse when
## the pan began (`depth`: how far ahead of the camera it is; < 0 - the view's target) follows the mouse
## one to one - the same feel however far in or out the view is zoomed.
func pan(rel: Vector2, depth := -1.0) -> void:
	var d := depth if depth > 0.0 else dist
	var s := (cam.size if cam.projection == Camera3D.PROJECTION_ORTHOGONAL else 2.0 * d * tan(deg_to_rad(cam.fov * 0.5))) / maxf(size.y, 1.0)
	target += (-cam.global_basis.x * rel.x + cam.global_basis.y * rel.y) * s
	update_camera()


## How far ahead of the camera (along its view) the model is under `at` - what a pan from there holds
## under the mouse; -1: nothing there.
func depth_at(w: Vector3) -> float:
	if w == Vector3.INF:
		return -1.0
	var d := (w - cam.global_position).dot(-cam.global_basis.z)
	return d if d > 0.0 else -1.0


## Zoomed by `f` (under 1: in) - towards `at` (a point in the world: what's under the mouse), which
## stays where it is on screen; Vector3.INF: towards the view's centre.
func zoom(f: float, at := Vector3.INF) -> void:
	if at != Vector3.INF:
		target = at + (target - at) * f   # (the camera and its target scaled about the point: it holds still on screen)
	dist *= f
	update_camera()


## Front (looking along -Z), side (along -X), top; `back` the opposite.
func set_view(which: String, back := false) -> void:
	match which:
		"front": yaw = PI if back else 0.0; pitch = 0.0
		"side": yaw = -PI / 2 if back else PI / 2; pitch = 0.0
		"top": yaw = 0.0; pitch = PI / 2 if back else -PI / 2
	update_camera()


## The camera framing `box` (world space).
func frame(box3: AABB) -> void:
	if box3.size == Vector3.ZERO and box3.position == Vector3.ZERO:
		return
	target = box3.get_center()
	var r := maxf(0.05, box3.size.length() * 0.5)
	dist = r / tan(deg_to_rad(cam.fov * 0.5)) * 1.15
	update_camera()


func ray(at: Vector2) -> Array:
	return [cam.project_ray_origin(at), cam.project_ray_normal(at)]


func project(p: Vector3) -> Vector2:
	return cam.unproject_position(p)


func behind(p: Vector3) -> bool:
	return cam.is_position_behind(p)


## Where the mouse ray meets the plane through `at` facing the camera.
## Where the ray under `at` meets the plane through `through` with normal `n` (null: it doesn't -
## the plane seen edge-on).
func on_plane(at: Vector2, through: Vector3, n: Vector3) -> Variant:
	var r := ray(at)
	return Plane(n.normalized(), through).intersects_ray(r[0], r[1])


func on_view_plane(at: Vector2, through: Vector3) -> Vector3:
	var r := ray(at)
	var pl := Plane(cam.global_basis.z, through)
	var hit = pl.intersects_ray(r[0], r[1])
	return hit if hit != null else through


## The point of the line `origin + t * dir` nearest the mouse ray.
func on_line(at: Vector2, origin: Vector3, dir: Vector3) -> Vector3:
	var r := ray(at)
	var p: Vector3 = r[0]
	var d: Vector3 = r[1]
	var w := origin - p
	var a := dir.dot(dir)
	var b := dir.dot(d)
	var c := d.dot(d)
	var dd := dir.dot(w)
	var e := d.dot(w)
	var den := a * c - b * b
	if absf(den) < 1e-9:
		return origin
	var t := (b * e - c * dd) / den
	return origin + dir * t


# --- the overlays -----------------------------------------------------------------

## Fills the edit-mode overlays (`em`: the edit mesh; `xf`: the part's
## transform; `kind`: 0 vertex / 1 edge / 2 face; the selection flags). Only the
## area under the mouse shows its wireframe and points: those within `radius` of
## `focus` (the part's own space; Vector3.INF - none), reached from `seeds` (the
## hovered triangle's points) along the edges, fading out towards the edge of it.
## The selection shows whole, wherever it is.
## `full`: the whole faint wireframe made again too (the mesh changed; not for a hover).
func show_overlays(em, xf: Transform3D, kind: int, sel_p: PackedByteArray, sel_e: PackedByteArray, sel_t: PackedByteArray,
		focus := Vector3.INF, radius := 0.0, seeds := PackedInt32Array(), full := true) -> void:
	for mi in [wire_all_mi, wire_mi, wire_back_mi, pts_mi, sel_edges_mi, sel_faces_mi, sel_pts_mi] + _sel_through:
		mi.visible = em != null
		mi.global_transform = xf
	if em != null and (full or wire_all_mi.mesh.get_surface_count() == 0):
		_lines(wire_all_mi.mesh, em.points, em.wire_edges(show_tris))
	if em == null:
		for mi in [wire_all_mi, wire_mi, pts_mi, sel_edges_mi, sel_faces_mi, sel_pts_mi]:
			_surface(mi.mesh, Mesh.PRIMITIVE_LINES, PackedVector3Array(), PackedInt32Array())
		request()
		return
	var n: int = em.points.size()
	# The hovered area: each point's strength (0 - outside).
	var near := PackedFloat32Array()
	near.resize(n)
	var area := PackedInt32Array()
	if focus != Vector3.INF and radius > 0.0:
		var seen := {}
		var stack: Array = Array(seeds)
		while not stack.is_empty() and area.size() < 20000:
			var p: int = stack.pop_back()
			if seen.has(p) or p < 0 or p >= n:
				continue
			seen[p] = true
			var d: float = (em.points[p] as Vector3).distance_to(focus)
			if d > radius:
				continue
			var k := 1.0 - d / radius
			near[p] = k * k * (3.0 - 2.0 * k)   # (smooth towards the rim)
			area.append(p)
			for j in range(em.adj_start[p], em.adj_start[p + 1]):
				stack.append(em.adj[j])
	var wire := PackedInt32Array()
	var wc := PackedColorArray()
	wc.resize(n)
	wc.fill(Color(1, 1, 1, 0))
	if not area.is_empty():
		for p in area:
			wc[p] = Color(1, 1, 1, near[p])
		var faces: bool = not show_tris and em.poly_count() < em.tri_count()
		for p in area:
			for j in range(em.adj_start[p], em.adj_start[p + 1]):
				var q: int = em.adj[j]
				if q > p and near[q] > 0.0:
					if faces and em.edge_inner[em.edge(p, q)]:
						continue   # (a diagonal inside a face)
					wire.append(p)
					wire.append(q)
	_surface(wire_mi.mesh, Mesh.PRIMITIVE_LINES, em.points, wire, wc)
	# the selected edges (edge mode: those picked; else those between selected points)
	var se := PackedInt32Array()
	var inner: PackedByteArray = em.edge_inner if not show_tris else PackedByteArray()
	if kind == 1 or kind == 3:
		for e in mini(sel_e.size(), em.edge_count()):
			if sel_e[e] and (inner.is_empty() or not inner[e]):
				se.append(em.edges[e * 2]); se.append(em.edges[e * 2 + 1])
	elif kind == 0:
		for e in em.edge_count():
			if sel_p[em.edges[e * 2]] and sel_p[em.edges[e * 2 + 1]] and (inner.is_empty() or not inner[e]):
				se.append(em.edges[e * 2]); se.append(em.edges[e * 2 + 1])
	_lines(sel_edges_mi.mesh, em.points, se)
	var st := PackedInt32Array()
	for t in sel_t.size():
		if sel_t[t]:
			st.append(em.tris[t * 3]); st.append(em.tris[t * 3 + 1]); st.append(em.tris[t * 3 + 2])
	_surface(sel_faces_mi.mesh, Mesh.PRIMITIVE_TRIANGLES, em.points, st)
	# The points: the hovered area's (vertex mode) and every selected one.
	var pi := PackedInt32Array()
	var c := PackedColorArray()
	c.resize(n)
	c.fill(Color(POINT, 0.0))
	if kind == 0 or kind == 3:
		for p in area:
			pi.append(p)
			c[p] = Color(POINT, near[p])
	for p in sel_p.size():
		if sel_p[p]:
			if near[p] <= 0.0 or (kind != 0 and kind != 3):
				pi.append(p)
			c[p] = SEL
	pts_mi.visible = not pi.is_empty()
	_surface(pts_mi.mesh, Mesh.PRIMITIVE_POINTS, em.points if not pi.is_empty() else PackedVector3Array(), pi, c)
	var sp := PackedInt32Array()
	for p in sel_p.size():
		if sel_p[p]:
			sp.append(p)
	sel_pts_mi.visible = not sp.is_empty()
	_surface(sel_pts_mi.mesh, Mesh.PRIMITIVE_POINTS, em.points if not sp.is_empty() else PackedVector3Array(), sp)
	request()


## Only the positions changed (a transform being dragged): the overlays follow
## (same indices, same colours).
func move_overlays(em) -> void:
	for m in _arrays:
		var e: Array = _arrays[m]
		var a: Array = e[1]
		a[Mesh.ARRAY_VERTEX] = em.points
		(m as ArrayMesh).clear_surfaces()
		(m as ArrayMesh).add_surface_from_arrays(e[0], a)
	request()


## Each overlay mesh's arrays (kept: refilling them doesn't read the GPU's copy back).
var _arrays := {}

func _lines(m: ArrayMesh, pts: PackedVector3Array, idx: PackedInt32Array) -> void:
	_surface(m, Mesh.PRIMITIVE_LINES, pts, idx)


func _surface(m: ArrayMesh, prim: int, pts: PackedVector3Array, idx: PackedInt32Array, col := PackedColorArray()) -> void:
	m.clear_surfaces()
	_arrays.erase(m)
	if (idx.is_empty() and prim != Mesh.PRIMITIVE_POINTS) or pts.is_empty():
		return
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = pts
	if not idx.is_empty():
		a[Mesh.ARRAY_INDEX] = idx
	if not col.is_empty():
		a[Mesh.ARRAY_COLOR] = col
	m.add_surface_from_arrays(prim, a)
	_arrays[m] = [prim, a]


# --- 2D, on top -------------------------------------------------------------------

# --- the gizmo: move, turn and scale the selection with the mouse ------------------------

## Where the gizmo stands (global; Vector3.INF - none) and the handle under the mouse.
var gizmo_at := Vector3.INF
var gizmo_hot := ""
## The gizmo's axes (global, its columns X / Y / Z): the world's, the part's own (object mode),
## or the selection's own (edit mode: along its surface, across it, its normal).
var gizmo_basis := Basis()
const GIZMO_PX := 90.0
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const AXIS_COL := [Color(0.95, 0.35, 0.35), Color(0.45, 0.9, 0.45), Color(0.4, 0.6, 1.0)]


## The gizmo's handles on screen: [{id, kind ("G" move / "R" turn / "S" scale), axis
## (Vector3.ZERO: free), pts (a polyline on screen), col, w}] - in the order they're picked.
func gizmo_handles() -> Array:
	if gizmo_at == Vector3.INF or cam == null or behind(gizmo_at):
		return []
	var c := project(gizmo_at)
	var d := cam.global_position.distance_to(gizmo_at)
	var wpp := (cam.size if cam.projection == Camera3D.PROJECTION_ORTHOGONAL else 2.0 * d * tan(deg_to_rad(cam.fov * 0.5))) / maxf(size.y, 1.0)
	var L := GIZMO_PX * wpp
	var out: Array = []
	for a in 3:
		var ax: Vector3 = gizmo_basis[a].normalized()
		var s0 := project(gizmo_at + ax * L * 0.62)
		var q := 5.0
		out.append({"id": "s" + "xyz"[a], "kind": "S", "axis": ax, "col": AXIS_COL[a], "w": 0.0,
			"pts": PackedVector2Array([s0 + Vector2(-q, -q), s0 + Vector2(q, -q), s0 + Vector2(q, q), s0 + Vector2(-q, q), s0 + Vector2(-q, -q)]), "box": true})
	for a in 3:
		var ax: Vector3 = gizmo_basis[a].normalized()
		out.append({"id": "m" + "xyz"[a], "kind": "G", "axis": ax, "col": AXIS_COL[a], "w": 3.0,
			"pts": PackedVector2Array([c, project(gizmo_at + ax * L)]), "arrow": true})
	for a in 3:
		var ax: Vector3 = gizmo_basis[a].normalized()
		var u: Vector3 = gizmo_basis[(a + 1) % 3].normalized()
		var v: Vector3 = gizmo_basis[(a + 2) % 3].normalized()
		var ring := PackedVector2Array()
		for i in 49:
			var t := TAU * i / 48.0
			ring.append(project(gizmo_at + (u * cos(t) + v * sin(t)) * L * 0.85))
		out.append({"id": "r" + "xyz"[a], "kind": "R", "axis": ax, "col": AXIS_COL[a], "w": 2.0, "pts": ring})
	var outer := PackedVector2Array()
	for i in 49:
		outer.append(c + Vector2(cos(TAU * i / 48.0), sin(TAU * i / 48.0)) * GIZMO_PX * 1.12)
	out.append({"id": "s", "kind": "S", "axis": Vector3.ZERO, "col": Color(1, 1, 1, 0.7), "w": 1.5, "pts": outer})
	var dot := PackedVector2Array()
	for i in 17:
		dot.append(c + Vector2(cos(TAU * i / 16.0), sin(TAU * i / 16.0)) * 7.0)
	out.append({"id": "m", "kind": "G", "axis": Vector3.ZERO, "col": Color(1, 1, 1, 0.9), "w": 2.0, "pts": dot, "fill": true})
	return out


## The handle under screen point `at` (within a few pixels), or {}.
func gizmo_pick(at: Vector2) -> Dictionary:
	var best := {}
	var bd := 9.0
	for h in gizmo_handles():
		var pts: PackedVector2Array = h["pts"]
		var d := INF
		if h.get("box", false) or h.get("fill", false):
			var r := Rect2(pts[0], Vector2.ZERO)
			for q in pts:
				r = r.expand(q)
			d = 0.0 if r.grow(3.0).has_point(at) else INF
		else:
			for i in pts.size() - 1:
				d = minf(d, at.distance_to(Geometry2D.get_closest_point_to_segment(at, pts[i], pts[i + 1])))
		if d < bd:
			bd = d
			best = h
	return best


func _draw_gizmo() -> void:
	for h in gizmo_handles():
		var pts: PackedVector2Array = h["pts"]
		var col: Color = h["col"]
		if h["id"] == gizmo_hot:
			col = Color(1.0, 0.9, 0.35)
		if h.get("box", false):
			draw_colored_polygon(pts.slice(0, 4), col)
			draw_polyline(pts, Color(0, 0, 0, 0.6), 1.0, true)
		elif h.get("fill", false):
			draw_colored_polygon(pts, Color(col, 0.35))
			draw_polyline(pts, col, h["w"], true)
		else:
			draw_polyline(pts, Color(0, 0, 0, 0.45), float(h["w"]) + 2.0, true)
			draw_polyline(pts, col, h["w"], true)
			if h.get("arrow", false):
				var a: Vector2 = pts[0]
				var b: Vector2 = pts[1]
				var dv := (b - a).normalized()
				var n := Vector2(-dv.y, dv.x)
				draw_colored_polygon(PackedVector2Array([b + dv * 10.0, b + n * 5.0, b - n * 5.0]), col)


## The knife's cut: the points placed so far joined up, a line on from the last to where the
## mouse would put the next, each point marked by how it snapped (a square on a point, a
## diamond on an edge, a dot on a face).
func _draw_knife() -> void:
	if not knife_on or cam == null:
		return
	var pts := PackedVector2Array()
	for p in knife_pts:
		if not behind(p):
			pts.append(project(p))
	var nxt := Vector2(-1, -1)
	if knife_next != Vector3.INF and not behind(knife_next):
		nxt = project(knife_next)
	elif knife_mouse.x >= 0.0:
		nxt = knife_mouse
	if pts.size() > 1:
		draw_polyline(pts, Color(0, 0, 0, 0.6), 4.0, true)
		draw_polyline(pts, KNIFE, 2.0, true)
	if not pts.is_empty() and nxt.x >= 0.0:
		var a := pts[pts.size() - 1]
		var l := a.distance_to(nxt)
		var d := (nxt - a) / maxf(l, 1.0)
		var s := 0.0
		while s < l:   # (dashed: not cut yet)
			var e := minf(s + 8.0, l)
			draw_line(a + d * s, a + d * e, Color(KNIFE, 0.85), 1.5, true)
			s += 13.0
	var marks := Array(pts)
	var kinds := Array(knife_kinds)
	if nxt.x >= 0.0:
		marks.append(nxt)
		kinds.append(knife_next_kind if knife_next != Vector3.INF else 2)
	for i in marks.size():
		var c: Vector2 = marks[i]
		var k: int = kinds[i] if i < kinds.size() else 2
		var col := KNIFE if i < pts.size() else Color(1, 1, 1, 0.9)
		if knife_through:
			draw_line(c + Vector2(-6, 0), c + Vector2(6, 0), col, 2.0)
			draw_line(c + Vector2(0, -6), c + Vector2(0, 6), col, 2.0)
		elif k == 0:
			draw_rect(Rect2(c - Vector2(4.5, 4.5), Vector2(9, 9)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(c - Vector2(3.5, 3.5), Vector2(7, 7)), col)
		elif k == 1:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)]), Color(0, 0, 0, 0.6))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4.5), c + Vector2(4.5, 0), c + Vector2(0, 4.5), c + Vector2(-4.5, 0)]), col)
		else:
			draw_circle(c, 4.5, Color(0, 0, 0, 0.6))
			draw_circle(c, 3.2, col)


func _draw_pre() -> void:
	if pre_kind < 0 or cam == null:
		return
	var q := PackedVector2Array()
	for p in pre_pts:
		if behind(p):
			return
		q.append(project(p))
	var col := Color(SEL, 0.4)
	match pre_kind:
		0:
			draw_circle(q[0], 6.0, col)
		1:
			draw_line(q[0], q[1], col, 5.0, true)
		2:
			for i in range(0, q.size() - 2, 3):
				draw_primitive(PackedVector2Array([q[i], q[i + 1], q[i + 2]]), PackedColorArray([Color(SEL, 0.25), Color(SEL, 0.25), Color(SEL, 0.25)]), PackedVector2Array())


## The model's stats, drawn in the view's top-left corner (MeshEditor.show_stats).
var stats := ""


func _draw_stats() -> void:
	if stats == "":
		return
	var f := get_theme_default_font()
	var fs := maxi(Settings.MIN_FONT, 13)
	var y := 84.0
	for line in stats.split("\n"):
		draw_string_outline(f, Vector2(14, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.7))
		draw_string(f, Vector2(14, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.92, 0.8, 0.9))
		y += fs + 4


## The axis a transform is locked to, drawn through what it moves: {at (global), dir, col} - {} none.
var axis_line := {}


func _draw_axis_line() -> void:
	if axis_line.is_empty() or cam == null:
		return
	var at: Vector3 = axis_line["at"]
	var d: Vector3 = (axis_line["dir"] as Vector3).normalized()
	var col: Color = axis_line["col"]
	var reach := maxf(cam.global_position.distance_to(at), 1.0) * 4.0
	var pts := PackedVector2Array()
	var n := 64
	for i in n + 1:   # (sampled: the part of the line behind the camera left out)
		var w := at + d * lerpf(-reach, reach, float(i) / n)
		if behind(w):
			if pts.size() >= 2:
				draw_polyline(pts, Color(0, 0, 0, 0.5), 4.0, true)
				draw_polyline(pts, col, 2.0, true)
			pts = PackedVector2Array()
			continue
		pts.append(project(w))
	if pts.size() >= 2:
		draw_polyline(pts, Color(0, 0, 0, 0.5), 4.0, true)
		draw_polyline(pts, col, 2.0, true)
	if not behind(at):
		draw_circle(project(at), 4.0, col)


## Curve deform's curve (mesh_editor.gd / deform_tools.gd fill it): its 4 control points (global:
## an end, its handle, the other handle, the other end) - empty: none; the one hovered or dragged.
var curve_pts := PackedVector3Array()
var curve_hot := -1
const CURVE := Color(0.4, 0.9, 1.0)


func _draw_curve() -> void:
	if curve_pts.size() != 4 or cam == null:
		return
	var cp := curve_pts
	var pts := PackedVector2Array()
	for i in 49:
		var t := i / 48.0
		var u := 1.0 - t
		var w := cp[0] * (u * u * u) + cp[1] * (3.0 * u * u * t) + cp[2] * (3.0 * u * t * t) + cp[3] * (t * t * t)
		if behind(w):
			continue
		pts.append(project(w))
	if pts.size() >= 2:
		draw_polyline(pts, Color(0, 0, 0, 0.55), 4.5, true)
		draw_polyline(pts, CURVE, 2.0, true)
	for h in [[0, 1], [3, 2]]:   # (each end's handle: a dashed line out to it, a round knob)
		if behind(cp[h[0]]) or behind(cp[h[1]]):
			continue
		var a := project(cp[h[0]])
		var b := project(cp[h[1]])
		draw_dashed_line(a, b, Color(1, 1, 1, 0.75), 1.5, 5.0)
		var hot: bool = curve_hot == h[1]
		draw_circle(b, 7.0 if hot else 5.5, Color(0, 0, 0, 0.6))
		draw_circle(b, 5.5 if hot else 4.0, SEL if hot else Color(1, 1, 1))
	for e in [0, 3]:   # (the ends: squares)
		if behind(cp[e]):
			continue
		var c := project(cp[e])
		var r := 7.0 if curve_hot == e else 5.5
		draw_rect(Rect2(c - Vector2(r + 1.5, r + 1.5), Vector2(r + 1.5, r + 1.5) * 2.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), SEL if curve_hot == e else CURVE)


func _draw() -> void:
	_draw_stats()
	_draw_axis_line()
	_draw_curve()
	_draw_pre()
	_draw_gizmo()
	_draw_knife()
	if box.size != Vector2.ZERO:
		var r := box.abs()
		draw_rect(r, Color(SEL, 0.12))
		draw_rect(r, SEL, false, 1.0)
	if circle_r > 0.0:
		draw_arc(circle_at, circle_r, 0, TAU, 72, Color(1, 1, 1, 0.75), 1.5, true)
		draw_arc(circle_at, circle_r + 1.5, 0, TAU, 72, Color(0, 0, 0, 0.5), 1.0, true)
	if hint != "":
		var f := get_theme_default_font()
		var fs := maxi(Settings.MIN_FONT, 15)
		draw_string(f, Vector2(14, size.y - 16), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.92, 0.8))
	# the axes, in the corner
	var o := Vector2(46, 46)
	var b := cam.global_basis.inverse() if cam else Basis()
	for ax in [[Vector3.RIGHT, Color(0.95, 0.35, 0.35), "X"], [Vector3.UP, Color(0.45, 0.9, 0.45), "Y"], [Vector3.BACK, Color(0.4, 0.6, 1.0), "Z"]]:
		var d: Vector3 = b * (ax[0] as Vector3)
		var e := o + Vector2(d.x, -d.y) * 30.0
		draw_line(o, e, ax[1], 2.0, true)
		draw_string(get_theme_default_font(), e + Vector2(-4, 5), ax[2], HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.MIN_FONT, ax[1])
