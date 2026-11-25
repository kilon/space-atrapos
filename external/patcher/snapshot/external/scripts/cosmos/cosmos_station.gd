class_name CosmosStation
extends Node3D
## A space station in the 3D game (Cosmos), built from its record (Galaxy's
## stations) - a hub along its axis, a turning habitat ring on spokes, modules,
## solar wings, a lit docking bay facing out, window lights, a beacon - in its
## empire's colours. Its parts and proportions vary with its seed and economy.

const SIZE := 420.0            # about this many metres across

var record := {}
var reach := SIZE              # (collisions, the HUD)
var bay := Vector3.ZERO        # the docking bay's mouth (local; facing -y)
var _ring: Node3D
var _spin := 0.05


func setup(st: Dictionary) -> void:
	record = st
	add_to_group("cam_solid")   # (the camera stops short of its parts)
	set_meta("cam_reach", 600.0)
	name = str(st.get("name", "Station")).replace(" ", "_")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(st.get("id", name)))
	var accent: Color = Galaxy.empire_color(str(st.get("empire", "")))
	var hull := _mat(Color(0.62, 0.64, 0.68), 0.55, 0.45)
	var dark := _mat(Color(0.22, 0.23, 0.26), 0.7, 0.5)
	var paint := _mat(accent.darkened(0.25), 0.3, 0.5)
	var lights := _mat(Color(1.0, 0.85, 0.55), 0.0, 0.5, Color(1.0, 0.8, 0.5) * 3.0)
	var trim := _mat(accent, 0.0, 0.5, accent * 2.5)
	var hub_len := rng.randf_range(220.0, 320.0)
	var hub_r := rng.randf_range(30.0, 46.0)
	_part(_cyl(hub_r, hub_r, hub_len, 24), hull, Vector3.ZERO)
	_part(_cyl(hub_r * 1.25, hub_r * 1.25, 20.0, 24), paint, Vector3(0, hub_len * 0.25, 0))
	_part(_cyl(hub_r * 1.25, hub_r * 1.25, 20.0, 24), paint, Vector3(0, -hub_len * 0.25, 0))
	_part(_cyl(hub_r * 0.5, hub_r, 40.0, 16), dark, Vector3(0, hub_len * 0.5 + 20.0, 0))
	# The docking bay: a box on the hub's top end, its mouth lit.
	_part(_box(Vector3(hub_r * 2.2, 50, hub_r * 2.2)), hull, Vector3(0, -hub_len * 0.5 - 25.0, 0))
	_part(_box(Vector3(hub_r * 1.6, 4, hub_r * 1.6)), trim, Vector3(0, -hub_len * 0.5 - 51.0, 0))
	bay = Vector3(0, -hub_len * 0.5 - 52.0, 0)
	# The habitat ring on its spokes - turning.
	_ring = Node3D.new()
	_ring.name = "Ring"
	add_child(_ring)
	var ring_r := rng.randf_range(150.0, 200.0)
	var tube := rng.randf_range(14.0, 22.0)
	var t := TorusMesh.new()
	t.inner_radius = ring_r - tube
	t.outer_radius = ring_r + tube
	t.rings = 96
	t.ring_segments = 12
	_part(t, hull, Vector3.ZERO, _ring)
	var w := TorusMesh.new()
	w.inner_radius = ring_r + tube - 1.0
	w.outer_radius = ring_r + tube + 1.2
	w.rings = 96
	w.ring_segments = 4
	_part(w, lights, Vector3.ZERO, _ring)
	var spokes := rng.randi_range(3, 6)
	for i in spokes:
		var a := TAU * i / spokes
		var sp := _part(_box(Vector3(ring_r - hub_r, 8, 10)), dark, Vector3(cos(a), 0, sin(a)) * (ring_r + hub_r) * 0.5, _ring)
		sp.rotation.y = -a
	# Modules along the hub, solar wings, a mast with its beacon.
	for i in rng.randi_range(2, 5):
		var y := rng.randf_range(-0.4, 0.4) * hub_len
		var a := rng.randf() * TAU
		var size := Vector3(rng.randf_range(30, 70), rng.randf_range(25, 50), rng.randf_range(30, 60))
		var m := _part(_box(size), hull if i % 2 == 0 else paint, Vector3(cos(a), 0, sin(a)) * (hub_r + size.x * 0.4) + Vector3(0, y, 0))
		m.rotation.y = -a
		_part(_box(Vector3(size.x * 0.8, 2.5, 1.0)), lights, m.position + Vector3(0, size.y * 0.2, 0) + Vector3(cos(a), 0, sin(a)) * 0.0).rotation.y = -a
	var wing := rng.randf_range(160.0, 240.0)
	for s in [-1.0, 1.0]:
		_part(_box(Vector3(6, 6, wing)), dark, Vector3(0, hub_len * 0.38, s * (hub_r + wing * 0.5)))
		var panel := _part(_box(Vector3(70, 1.5, wing * 0.8)), _mat(Color(0.12, 0.16, 0.32), 0.8, 0.25), Vector3(0, hub_len * 0.38, s * (hub_r + wing * 0.55)))
		panel.rotation.z = 0.35
	_part(_cyl(1.5, 1.5, 80.0, 6), dark, Vector3(0, hub_len * 0.5 + 80.0, 0))
	var beacon := _part(_sphere(5.0), _mat(Color(1, 0.2, 0.15), 0.0, 0.5, Color(1.0, 0.15, 0.1) * 6.0), Vector3(0, hub_len * 0.5 + 122.0, 0))
	beacon.name = "Beacon"
	reach = maxf(ring_r + tube, hub_len * 0.5 + 120.0)
	_spin = rng.randf_range(0.03, 0.07)
	rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))


func _process(delta: float) -> void:
	if _ring:
		_ring.rotate_y(_spin * delta)


func _part(mesh: Mesh, mat: Material, at: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	(parent if parent else self).add_child(mi)
	return mi


static func _mat(c: Color, metal: float, rough: float, glow := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if glow != Color.BLACK:
		m.emission_enabled = true
		m.emission = glow
	return m


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _cyl(top: float, bottom: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s
