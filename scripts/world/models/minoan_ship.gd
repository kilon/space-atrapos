class_name MinoanShip
extends RefCounted
## Your ship, a Minoan armoured hauler (~58 m): a long hull of chamfered plates
## (cream, worn, red bands), the bridge's windows wrapped over its nose, a
## raised spine with masts, four engine nacelles at the back (two a side,
## stacked), the triskelion on its flanks, amber lamps in rows along it, cargo
## pods under the belly, the tail a door (the ramp: CosmosShipInterior). Built
## as data (`build` - a worker's): one mesh, the glass apart.

## The hull: [z, half width, top, bottom, chamfer] (ship space, metres, -z the nose).
const HULL := [[-28.0, 1.8, 0.2, -1.2, 0.6], [-25.5, 4.8, 2.0, -2.4, 1.4], [-21.0, 6.8, 3.9, -3.0, 1.9],
	[-12.0, 7.4, 4.5, -3.1, 1.6], [4.0, 7.6, 4.6, -3.2, 1.6], [16.0, 7.2, 4.4, -3.0, 1.6], [22.4, 6.2, 3.8, -2.8, 1.6]]
const SPINE := [[-15.0, 1.0, 4.9, 3.8, 0.4], [-11.0, 3.2, 6.4, 3.8, 1.0], [9.0, 3.4, 6.6, 3.8, 1.0], [14.5, 2.4, 5.8, 3.8, 0.8]]
## The nacelles' middles (x, y): two a side.
const NACELLES := [Vector2(-10.1, -0.4), Vector2(10.1, -0.4), Vector2(-9.7, 5.0), Vector2(9.7, 5.0)]
const NACELLE_R := 2.5
const NOZZLE_Z := 29.2
const LENGTH := 58.0                     # (nose to nozzles)
static var _mesh: ArrayMesh
static var _glass: ArrayMesh
## The tail's door (x half width, y from, y to) - the inside's aft room.
const DOOR := [3.4, -1.4, 2.0]


static func build() -> Dictionary:
	var m := EmpireKit.Mesher.new()
	var g := EmpireKit.Mesher.new()
	# The hull: the nose's top faces glass (the bridge's windows), bands of red.
	var zone_of := func(seg: int, f: int) -> int:
		if seg <= 1 and (f == EmpireKit.TOP or f in EmpireKit.UPPER):
			return -1
		if f == EmpireKit.TOP:
			return EmpireKit.MAIN
		if f in EmpireKit.UPPER:
			return EmpireKit.ACCENT if seg in [2, 4] else EmpireKit.MAIN
		if f in EmpireKit.LOWER:
			return EmpireKit.ACCENT if seg == 1 else EmpireKit.MAIN
		if f == 4:
			return EmpireKit.IRON
		return EmpireKit.ACCENT if seg == 1 else EmpireKit.MAIN
	m.loft(HULL, zone_of, true, false)
	for seg in 2:
		var r0 := EmpireKit.Mesher.ring(HULL[seg])
		var r1 := EmpireKit.Mesher.ring(HULL[seg + 1])
		var inner := Vector3(0, -0.5, (float(HULL[seg][0]) + float(HULL[seg + 1][0])) * 0.5)
		for f in [7, 0, 1]:
			var j: int = (f + 1) % 8
			g.quad(r0[f], r0[j], r1[j], r1[f], 0, inner)
		# (the windows' frames: steel ribs across and along)
		for f in [7, 0, 1]:
			m.cyl(r1[f], r1[(f + 1) % 8], 0.09, 0.09, EmpireKit.STEEL, 4, false)
			if seg == 0:
				m.cyl(r0[f], r0[(f + 1) % 8], 0.09, 0.09, EmpireKit.STEEL, 4, false)
		for f in [7, 0, 1, 2]:
			m.cyl(r0[f], r1[f], 0.09, 0.09, EmpireKit.STEEL, 4, false)
	_plates(m)
	_tail(m)
	# The spine and its masts.
	m.loft(SPINE, func(seg: int, f: int) -> int:
		if f in EmpireKit.SIDES or f in EmpireKit.UPPER:
			return EmpireKit.ACCENT if seg == 1 and f in EmpireKit.SIDES else EmpireKit.MAIN
		return EmpireKit.MAIN if f == EmpireKit.TOP else EmpireKit.IRON)
	for mast in [[-3.0, 10.6, 0.12], [-1.2, 9.2, 0.1], [0.8, 8.4, 0.09], [6.0, 7.8, 0.15]]:
		m.cyl(Vector3(0.6, 6.4, mast[0]), Vector3(0.6, mast[1], mast[0]), mast[2], mast[2] * 0.4, EmpireKit.STEEL, 6)
	m.boxat(Vector3(2.2, 0.5, 4.0), Vector3(0, 6.7, 4.0), EmpireKit.IRON)
	m.boxat(Vector3(1.4, 0.4, 2.0), Vector3(-1.0, 6.6, -6.0), EmpireKit.IRON)
	for z in [-9.0, -4.0, 1.0, 6.0]:   # (the spine's lamps)
		for sx in [-1.0, 1.0]:
			var s := EmpireKit.section_at(SPINE, z)
			m.boxat(Vector3(0.08, 0.12, 2.6), Vector3(sx * (float(s[1]) + 0.02), 4.4, z), EmpireKit.LAMP)
	# Plates on the flanks, the roundels, the lamps in rows.
	for sx in [-1.0, 1.0]:
		var rs := EmpireKit.section_at(HULL, 7.0)
		m.disc(Vector3(sx * (float(rs[1]) + 0.17), 0.7, 7.0), Vector3(sx, 0, 0), Vector3.UP, 2.2, EmpireKit.ROUNDEL, 40)
		for z in range(-22, 20, 3):
			if absf(z - 7.0) < 3.0:
				continue
			var s := EmpireKit.section_at(HULL, z)
			var w: float = s[1]
			var lo: float = float(s[3]) + float(s[4])
			m.boxat(Vector3(0.2, 0.1, 1.6), Vector3(sx * (w + 0.08), lo + 0.25, z + 0.5), EmpireKit.LAMP)
		for z in [-17.5, -15.5, -13.5]:   # (the bridge's side windows, lit)
			var s := EmpireKit.section_at(HULL, z)
			m.boxat(Vector3(0.14, 0.5, 1.4), Vector3(sx * (float(s[1]) + 0.1), 2.1, z), EmpireKit.LAMP)
		# (the vents and hatches)
		var vs := EmpireKit.section_at(HULL, -9.0)
		m.boxat(Vector3(0.3, 1.0, 2.4), Vector3(sx * (float(vs[1]) + 0.12), -0.6, -9.0), EmpireKit.IRON)
		m.boxat(Vector3(0.3, 2.2, 1.2), Vector3(sx * (float(vs[1]) + 0.12), 1.0, 2.4), EmpireKit.IRON)
	# The belly: pods, keel, lamps.
	for pod in [[-15.0, 9.0, 6.4], [-2.0, 10.0, 7.6], [11.0, 9.0, 6.8]]:
		m.boxat(Vector3(pod[2], 0.8, pod[1]), Vector3(0, -3.5, pod[0]), EmpireKit.IRON)
		m.boxat(Vector3(pod[2] - 1.0, 0.1, pod[1] - 1.0), Vector3(0, -3.92, pod[0]), EmpireKit.LAMP if int(pod[0]) == -2 else EmpireKit.IRON)
	# The nacelles: on pylons from the flanks, cream cowls, a red band, steel rings, the nozzles.
	for nc: Vector2 in NACELLES:
		var sx := signf(nc.x)
		var s := EmpireKit.section_at(HULL, 17.0)
		m.boxat(Vector3(absf(nc.x) - float(s[1]) + 0.6, 1.4, 9.0), Vector3((absf(nc.x) + float(s[1])) * 0.5 * sx, nc.y, 18.5), EmpireKit.IRON)
		var r := NACELLE_R
		m.lathe(nc.x, nc.y, [[9.5, 0.0, EmpireKit.MAIN], [9.5, r * 0.55, EmpireKit.MAIN], [11.5, r * 0.92, EmpireKit.MAIN],
			[13.0, r, EmpireKit.MAIN], [16.5, r, EmpireKit.ACCENT], [17.0, r * 1.02, EmpireKit.STEEL], [17.6, r * 1.02, EmpireKit.STEEL],
			[17.6, r, EmpireKit.MAIN], [24.5, r, EmpireKit.MAIN], [24.5, r * 1.1, EmpireKit.STEEL], [26.5, r * 1.1, EmpireKit.STEEL],
			[27.0, r * 1.05, EmpireKit.IRON], [NOZZLE_Z, r * 0.98, EmpireKit.IRON], [NOZZLE_Z, r * 0.8, EmpireKit.IRON],
			[NOZZLE_Z - 1.6, r * 0.45, EmpireKit.IRON], [NOZZLE_Z - 1.6, 0.0, EmpireKit.IRON]], 16)
		m.boxat(Vector3(0.1, 0.14, 5.0), Vector3(nc.x + sx * r, nc.y, 21.0), EmpireKit.LAMP)
	return {"hull": m.arrays(), "glass": g.arrays()}


## Armour plates over the flanks and chamfers (raised, gaps between - the
## plating's seams), mostly cream, some red; none where the roundel is.
static func _plates(m: EmpireKit.Mesher) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in range(2, HULL.size() - 1):
		var r0 := EmpireKit.Mesher.ring(HULL[k])
		var r1 := EmpireKit.Mesher.ring(HULL[k + 1])
		var z0: float = HULL[k][0]
		var z1: float = HULL[k + 1][0]
		var inner := Vector3(0, 0.5, (z0 + z1) * 0.5)
		var n := maxi(1, roundi((z1 - z0) / 3.4))
		for f in [1, 2, 3, 5, 6, 7]:
			var j: int = (f + 1) % 8
			var rows := 2 if f in EmpireKit.SIDES else 1
			for i in n:
				for row in rows:
					var t0 := (i + 0.04) / n
					var t1 := (i + 0.96) / n
					var s0 := (row + 0.06) / rows
					var s1 := (row + 0.94) / rows
					var zc := lerpf(z0, z1, (t0 + t1) * 0.5)
					if f in EmpireKit.SIDES and absf(zc - 7.0) < 3.2:
						continue   # (the roundel's place)
					if rng.randf() < 0.25:
						continue   # (the bare hull showing)
					var p := func(s: float, t: float) -> Vector3:
						return ((r0[f] as Vector3).lerp(r0[j], s)).lerp((r1[f] as Vector3).lerp(r1[j], s), t)
					var zone := EmpireKit.ACCENT if rng.randf() < 0.18 else EmpireKit.MAIN
					m.plate(p.call(s0, t0), p.call(s1, t0), p.call(s1, t1), p.call(s0, t1), 0.1, zone, inner)


## The hull as meshes (made once a run, shared - the Minoan haulers wear it too).
static func meshes() -> Array:
	if _mesh == null:
		var a: Dictionary = CosmosShip.hull_arrays()
		_mesh = ArrayMesh.new()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a["hull"])
		_mesh.set_meta("verts", a["hull"][Mesh.ARRAY_VERTEX])   # (its shape, for the rooms inside it: CosmosNpcInterior)
		LodKit.later(_mesh, [a["hull"]])   # (its levels of detail - LodKit)
		_glass = ArrayMesh.new()
		_glass.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a["glass"])
		_glass.set_meta("hull_verts", a["glass"][Mesh.ARRAY_VERTEX])   # (its windows solid too: CosmosHullGrid)
		_mesh.set_meta("seal", seal())   # (the tail's doorway closed - open only while its ramp's down)
	return [_mesh, _glass]


## The tail's doorway as two triangles (ship space): what closes it for the hull's
## solid (CosmosHullGrid) - the door itself is the inside's.
static func seal() -> PackedVector3Array:
	var z: float = HULL[HULL.size() - 1][0]
	var x: float = DOOR[0]
	var a := Vector3(-x, DOOR[1], z)
	var b := Vector3(x, DOOR[1], z)
	var c := Vector3(x, DOOR[2], z)
	var d := Vector3(-x, DOOR[2], z)
	return PackedVector3Array([a, b, c, a, c, d])


## Another ship of this kind into `root`, scaled `k` (its middle at the root's,
## no rooms inside - dark behind its windows): the nozzles' places, for their glows.
static func place(root: Node3D, k: float) -> Array:
	var ms := meshes()
	var holder := Node3D.new()
	holder.name = "MinoanHull"
	holder.scale = Vector3.ONE * k
	holder.position = Vector3(0, 0, -0.5 * k)   # (nose -28 .. nozzles +29: about its middle)
	root.add_child(holder)
	var body := MeshInstance3D.new()
	body.mesh = ms[0]
	body.material_override = EmpireKit.mat("hull")
	holder.add_child(body)
	var gl := MeshInstance3D.new()
	gl.mesh = ms[1]
	gl.material_override = EmpireKit.glass()
	gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(gl)
	var out: Array = []
	for nc: Vector2 in NACELLES:
		out.append(holder.position + Vector3(nc.x, nc.y, NOZZLE_Z + 0.2) * k)
	return out


## The tail: a plate round the door (the door itself the inside's).
static func _tail(m: EmpireKit.Mesher) -> void:
	var s: Array = HULL[HULL.size() - 1]
	var r := EmpireKit.Mesher.ring(s)
	var z: float = s[0]
	var x: float = DOOR[0]
	var y0: float = DOOR[1]
	var y1: float = DOOR[2]
	var tl := Vector3(-x, y1, z)
	var tr := Vector3(x, y1, z)
	var br := Vector3(x, y0, z)
	var bl := Vector3(-x, y0, z)
	var inner := [tl, tr, tr, br, br, bl, bl, tl]
	var behind := Vector3(0, 0, z - 1.0)
	for f in 8:
		var j: int = (f + 1) % 8
		m.quad(r[f], r[j], inner[j], inner[f], EmpireKit.IRON, behind)
	# (the door's frame, lit)
	m.boxat(Vector3(x * 2.0 + 0.6, 0.3, 0.3), Vector3(0, y1 + 0.15, z + 0.1), EmpireKit.STEEL)
	for sx in [-1.0, 1.0]:
		m.boxat(Vector3(0.3, y1 - y0, 0.3), Vector3(sx * (x + 0.15), (y0 + y1) * 0.5, z + 0.1), EmpireKit.STEEL)
		m.boxat(Vector3(0.08, y1 - y0 - 0.4, 0.1), Vector3(sx * (x + 0.36), (y0 + y1) * 0.5, z + 0.12), EmpireKit.LAMP)
