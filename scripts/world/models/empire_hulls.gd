class_name EmpireHulls
extends RefCounted
## The empires' ships (the 3D game's other ships: traders, patrols, raiders),
## each empire's from its reference sheet (external/images/<empire>_ships_1.png)
## in its look (EmpireKit: colours, emblem, frieze):
##   Athens - marble and navy, scythe wings curving forward, the owl; the big
##     ones carry a temple's colonnade;
##   Sparta - an iron frame under cream and crimson plates, the lambda on an
##     eight-sided shield, swept wings, guns along its sides;
##   Minoa - cream and red, twin prow horns, the double axe's blades for wings
##     (its haulers: your ship's kind - MinoanShip);
##   Mycenae - blocks of stone banded in gold, boar's tusks at the bow, a gold
##     dome with the rosette;
##   Ionia - marble and lapis, an Ionic column across the hull, volutes at the
##     tips of its curling wings;
##   the Cyclades - one smooth piece of white marble, a curled prow, oars of
##     ribs, the spiral;
##   the Sea Peoples - dark iron and red, scythes, bone spikes, a tattered sail,
##     the skull; and the independents' plain grey hulls.
## A design is small ("fighter", "patrol", "pirate") or big (the traders), in
## two variants; each is one mesh (+ its glass), made on a worker (`warm`),
## shared by every ship of its kind and scaled to the ship. Built in unit
## space - the nose at z -1, the nozzles at +1 - then to its nominal size.

const SMALL := 13.0            # the nominal half length (m) a design's seams and marks are made for
const BIG := 40.0
const VARIANTS := 2

static var _cache := {}        # key -> {task, out: [arrays...], mesh, glass}


static func _key(emp: String, big: bool, v: int) -> String:
	return "%s|%d|%d" % [emp, int(big), v]


static func _emp(empire: String) -> String:
	return empire if EmpireKit.LOOKS.has(empire) else ""


## Starts the builds of an empire's ships (and the raiders', the independents') on workers.
static func warm(empires: Array) -> void:
	for e in empires:
		var emp := _emp(str(e))
		for big in [false, true]:
			if big and emp == Galaxy.HOME_EMPIRE:
				continue   # (the Minoan haulers: MinoanShip)
			for v in VARIANTS:
				if OS.has_feature("web"):
					_later.append([emp, big, v])   # (a browser: one at a time once the game's in - pump; a dozen at once held its main thread back)
				else:
					_start(emp, big, v)


static var _later: Array = []
static var _pumped := -1


## (A browser; Cosmos, a few times a second once it's built) The next queued design
## started when the last is done - unless something has asked for it already.
static func pump() -> void:
	if _pumped >= 0 and not Jobs.done(_pumped):
		return
	_pumped = -1
	while not _later.is_empty():
		var q: Array = _later.pop_front()
		if _cache.has(_key(q[0], q[1], q[2])):
			continue
		_pumped = int(_start(q[0], q[1], q[2])["task"])
		return


static func _start(emp: String, big: bool, v: int) -> Dictionary:
	var k := _key(emp, big, v)
	if _cache.has(k):
		return _cache[k]
	var entry := {"task": -1, "out": [], "mesh": null, "glass": null}
	_cache[k] = entry
	var out: Array = entry["out"]
	entry["task"] = Jobs.add(func(): out.append_array(build(emp, big, v)), false, "ship design")
	return entry


static func _meshes(emp: String, big: bool, v: int) -> Array:
	var e := _start(emp, big, v)
	if int(e["task"]) >= 0:
		Jobs.wait(int(e["task"]))
		e["task"] = -1
	if e["mesh"] == null:
		var out: Array = e["out"]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out[0])
		m.set_meta("verts", out[0][Mesh.ARRAY_VERTEX])   # (its shape, for the rooms inside it: CosmosNpcInterior)
		LodKit.later(m, [out[0]])   # (its levels of detail - LodKit)
		e["mesh"] = m
		if not (out[1][Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			var g := ArrayMesh.new()
			g.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out[1])
			g.set_meta("hull_verts", out[1][Mesh.ARRAY_VERTEX])   # (its canopy solid too: CosmosHullGrid)
			e["glass"] = g
	return [e["mesh"], e["glass"]]


## True once every design a ship of `empire` and `kind` could wear is made
## (else their builds are started): a ship is launched when its hull is ready,
## not waited for.
static func ready(empire: String, kind: String) -> bool:
	var emp := _emp(empire)
	var big := kind in ["trader", "freighter", "hauler"]
	var ok := true
	for v in VARIANTS:
		var e := _start(emp, big, v)
		if int(e["task"]) >= 0 and not Jobs.done(int(e["task"])):
			ok = false
	return ok


## Every build done (tests, leaving the game: no task left running).
static func finish() -> void:
	for k in _cache:
		if int(_cache[k]["task"]) >= 0:
			Jobs.wait(int(_cache[k]["task"]))
			_cache[k]["task"] = -1


## A ship of `empire` ("pirates": a raider's) into `root`, `reach` its half
## length (m): the nozzles' places, for their glows.
static func place(root: Node3D, empire: String, kind: String, reach: float, seed: int) -> Array:
	var emp := _emp(empire)
	var big := kind in ["trader", "freighter", "hauler"]
	var v := absi(seed) % VARIANTS
	var ms := _meshes(emp, big, v)
	var nominal := BIG if big else SMALL
	var holder := Node3D.new()
	holder.name = "Hull"
	holder.scale = Vector3.ONE * (reach / nominal)
	root.add_child(holder)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = ms[0]
	body.material_override = EmpireKit.mat("hull", emp)
	holder.add_child(body)
	if ms[1] != null:
		var gl := MeshInstance3D.new()
		gl.mesh = ms[1]
		gl.material_override = EmpireKit.glass()
		gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(gl)
	var out: Array = []
	for e in engines(emp, big, v):
		out.append(Vector3(e[0], e[1], 1.02) * reach)
	return out


## Where a design's engines are (unit space): [x, y, radius].
static func engines(emp: String, big: bool, v: int) -> Array:
	var r := 0.085 if big else 0.07
	match emp:
		"sparta", "pirates":
			return [[-0.2, 0.0, r], [0.0, 0.02, r * 1.1], [0.2, 0.0, r]] if not big else [[-0.26, 0.0, r], [-0.09, 0.0, r], [0.09, 0.0, r], [0.26, 0.0, r]]
		"cyclades":
			return [[-0.11, -0.01, r * 0.8], [0.0, 0.03, r * 0.8], [0.11, -0.01, r * 0.8]]
		"mycenae":
			return [[-0.17, 0.0, r * 1.15], [0.17, 0.0, r * 1.15]] if not big else [[-0.24, 0.0, r * 1.1], [0.0, 0.0, r * 1.1], [0.24, 0.0, r * 1.1]]
	if big:
		return [[-0.24, 0.0, r], [0.0, 0.04, r], [0.24, 0.0, r]]
	return [[-0.17, 0.0, r], [0.17, 0.0, r]] if v == 0 else [[-0.19, 0.0, r * 0.9], [0.0, 0.03, r * 0.9], [0.19, 0.0, r * 0.9]]


# --- The builds ----------------------------------------------------------------------

## [hull arrays, glass arrays] of a design, at its nominal size.
static func build(emp: String, big: bool, v: int) -> Array:
	var m := EmpireKit.Mesher.new()
	var g := EmpireKit.Mesher.new()
	match emp:
		"athens": _athens(m, g, big, v)
		"sparta": _sparta(m, g, big, v)
		"minoa": _minoa(m, g, v)
		"mycenae": _mycenae(m, g, big, v)
		"ionia": _ionia(m, g, big, v)
		"cyclades": _cyclades(m, g, big, v)
		"pirates": _pirates(m, g, big, v)
		_: _plain(m, g, big, v)
	var zone := EmpireKit.MAIN if emp != "sparta" and emp != "pirates" else EmpireKit.IRON
	for e in engines(emp, big, v):
		_nacelle(m, e[0], e[1], e[2], zone)
	var s := BIG if big else SMALL
	var out := [m.arrays(), g.arrays()]
	for a in out:
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for i in vs.size():
			vs[i] *= s
		a[Mesh.ARRAY_VERTEX] = vs
	return out


## An engine: a cowl from the hull's shoulder back to its nozzle (a band, a ring, the dark throat).
static func _nacelle(m: EmpireKit.Mesher, x: float, y: float, r: float, zone: int) -> void:
	m.lathe(x, y, [[0.42, 0.0, zone], [0.42, r * 0.55, zone], [0.52, r * 0.95, zone], [0.6, r, zone], [0.7, r, EmpireKit.ACCENT],
		[0.72, r * 1.04, EmpireKit.GOLD], [0.76, r * 1.04, EmpireKit.GOLD], [0.76, r, zone], [0.9, r, zone], [0.9, r * 1.1, EmpireKit.STEEL],
		[0.95, r * 1.1, EmpireKit.STEEL], [0.96, r * 1.02, EmpireKit.IRON], [1.02, r * 0.92, EmpireKit.IRON], [1.02, r * 0.74, EmpireKit.IRON],
		[0.95, r * 0.4, EmpireKit.IRON], [0.95, 0.0, EmpireKit.LAMP]], 12)


## The fuselage: [z, half width, top, bottom, chamfer] sections, the faces' zones by `zones`
## [top, upper chamfers, sides, lower chamfers, bottom]; a band of `band` zone on the sides of segment `band_at`.
static func _fuselage(m: EmpireKit.Mesher, secs: Array, zones: Array, band_at := -1, band := EmpireKit.ACCENT) -> void:
	m.loft(secs, func(seg: int, f: int) -> int:
		if seg == band_at and (f in EmpireKit.SIDES or f in EmpireKit.UPPER):
			return band
		if f == EmpireKit.TOP:
			return zones[0]
		if f in EmpireKit.UPPER:
			return zones[1]
		if f in EmpireKit.SIDES:
			return zones[2]
		if f in EmpireKit.LOWER:
			return zones[3]
		return zones[4])


static func _secs(big: bool, w := 1.0, h := 1.0) -> Array:
	if big:
		return [[-1.0, 0.03 * w, 0.02 * h, -0.03 * h, 0.015], [-0.8, 0.12 * w, 0.08 * h, -0.08 * h, 0.05], [-0.45, 0.2 * w, 0.14 * h, -0.12 * h, 0.06],
			[0.3, 0.22 * w, 0.15 * h, -0.13 * h, 0.06], [0.62, 0.2 * w, 0.13 * h, -0.12 * h, 0.06], [0.78, 0.15 * w, 0.1 * h, -0.09 * h, 0.05]]
	return [[-1.0, 0.012 * w, 0.008 * h, -0.016 * h, 0.006], [-0.72, 0.065 * w, 0.045 * h, -0.045 * h, 0.028], [-0.3, 0.115 * w, 0.085 * h, -0.07 * h, 0.04],
		[0.2, 0.135 * w, 0.095 * h, -0.08 * h, 0.042], [0.58, 0.12 * w, 0.085 * h, -0.07 * h, 0.04], [0.78, 0.09 * w, 0.065 * h, -0.055 * h, 0.03]]


## The canopy: a blister of glass over the bow (dark under it), its frame.
static func _canopy(m: EmpireKit.Mesher, g: EmpireKit.Mesher, z0: float, z1: float, w: float, y: float, h: float) -> void:
	var secs := [[z0, w * 0.35, y + h * 0.25, y - 0.01, w * 0.2], [lerpf(z0, z1, 0.4), w, y + h, y - 0.01, w * 0.45], [z1, w * 0.7, y + h * 0.6, y - 0.01, w * 0.3]]
	g.loft(secs, func(_s: int, _f: int) -> int: return 0)
	m.boxat(Vector3(w * 1.5, 0.006, (z1 - z0) * 0.9), Vector3(0, y + 0.002, (z0 + z1) * 0.5), EmpireKit.IRON)
	m.boxat(Vector3(w * 2.1, 0.012, 0.012), Vector3(0, y + h * 0.75, lerpf(z0, z1, 0.4)), EmpireKit.STEEL)


## A band along an arc, from thick to a point (a scythe, a horn) or thick in
## the middle (`sym`: a crescent, an axe's blade) - an outline for a slab.
static func crescent(c: Vector2, r: float, a0: float, a1: float, t0: float, n := 12, pw := 0.8, sym := false) -> PackedVector2Array:
	var outer: Array = []
	var inner: Array = []
	for i in n + 1:
		var s := float(i) / n
		var a := lerpf(a0, a1, s)
		var t := t0 * (pow(sin(PI * s), pw) if sym else pow(1.0 - s, pw))
		t = maxf(t, t0 * 0.02)
		var d := Vector2(cos(a), sin(a))
		outer.append(c + d * (r + t * 0.5))
		inner.append(c + d * (r - t * 0.5))
	inner.reverse()
	return PackedVector2Array(outer + inner)


## A wing each side: `pts` (x >= 0 out, y = z) mirrored, at height `y`, a dihedral, the face `zone`, the rim `edge`.
static func _wings(m: EmpireKit.Mesher, pts: PackedVector2Array, y: float, t: float, zone: int, edge: int, dihedral := 0.0) -> void:
	for sx in [-1.0, 1.0]:
		var q := PackedVector2Array()
		for p in pts:
			q.append(Vector2(p.x * sx, p.y))
		m.slab(q, Transform3D(Basis(Vector3(0, 0, 1), dihedral * sx), Vector3(0, y, 0)), t, zone, edge)


## The emblem: a disc on top of the hull, and one on each flank.
static func _marks(m: EmpireKit.Mesher, z: float, top: float, r: float, side_x: float, side_r: float) -> void:
	m.cyl(Vector3(0, top - 0.004, z), Vector3(0, top + 0.006, z), r * 1.08, r * 1.08, EmpireKit.GOLD, 24)
	m.disc(Vector3(0, top + 0.0075, z), Vector3.UP, Vector3.FORWARD, r, EmpireKit.ROUNDEL, 28)
	if side_r > 0.0:
		for sx in [-1.0, 1.0]:
			m.disc(Vector3(sx * side_x, 0.0, z), Vector3(sx, 0, 0), Vector3.UP, side_r, EmpireKit.ROUNDEL, 20)


## Lamps along the flanks.
static func _lamps(m: EmpireKit.Mesher, secs: Array, from: float, to: float, n: int, y := -0.01) -> void:
	for i in n:
		var z := lerpf(from, to, (i + 0.5) / n)
		var s := EmpireKit.section_at(secs, z)
		for sx in [-1.0, 1.0]:
			m.boxat(Vector3(0.008, 0.012, (to - from) / n * 0.5), Vector3(sx * (float(s[1]) + 0.002), y, z), EmpireKit.LAMP)


## Cargo modules along a big ship's flanks.
static func _cargo(m: EmpireKit.Mesher, x: float, zone_a: int, zone_b: int, n := 3) -> void:
	for sx in [-1.0, 1.0]:
		for k in n:
			var z := -0.42 + k * 0.3
			m.boxat(Vector3(0.12, 0.16, 0.26), Vector3(sx * x, -0.01, z), zone_a if k % 2 == 0 else zone_b)
			m.boxat(Vector3(0.126, 0.166, 0.03), Vector3(sx * x, -0.01, z), EmpireKit.GOLD)   # (a band round its middle)
			m.boxat(Vector3(0.008, 0.02, 0.18), Vector3(sx * (x + 0.062), -0.03, z), EmpireKit.LAMP)


static func _athens(m: EmpireKit.Mesher, g: EmpireKit.Mesher, big: bool, v: int) -> void:
	var secs := _secs(big)
	_fuselage(m, secs, [EmpireKit.MAIN, EmpireKit.ACCENT, EmpireKit.MAIN, EmpireKit.MAIN, EmpireKit.IRON], 1, EmpireKit.GOLD)
	var top: float = EmpireKit.section_at(secs, 0.1)[2]
	if big:
		# A temple amidships: its colonnade down both sides, the entablature, a navy roof.
		var hw := 0.24
		m.boxat(Vector3(hw * 2.0, 0.02, 0.72), Vector3(0, top + 0.01, 0.0), EmpireKit.MAIN)
		m.boxat(Vector3(hw * 1.3, 0.11, 0.6), Vector3(0, top + 0.075, 0.0), EmpireKit.MAIN)
		for sx in [-1.0, 1.0]:
			for k in 7:
				var z := -0.31 + k * 0.103
				m.cyl(Vector3(sx * (hw - 0.03), top + 0.02, z), Vector3(sx * (hw - 0.03), top + 0.13, z), 0.017, 0.014, EmpireKit.MAIN, 8, false)
			m.panel(Vector3(sx * (hw + 0.002), top + 0.15, 0.0), Vector3(0, 0, 0.36), Vector3(0, -0.016, 0), EmpireKit.FRIEZE, Vector3(sx, 0, 0), 14.0 / 40.0)
		m.boxat(Vector3(hw * 2.0, 0.035, 0.74), Vector3(0, top + 0.148, 0.0), EmpireKit.MAIN)
		m.boxat(Vector3(hw * 2.06, 0.01, 0.76), Vector3(0, top + 0.17, 0.0), EmpireKit.GOLD)
		for sx in [-1.0, 1.0]:
			m.box(Vector3(hw * 1.06, 0.012, 0.76), Transform3D(Basis(Vector3(0, 0, 1), -sx * 0.28), Vector3(sx * hw * 0.5, top + 0.21, 0.0)), EmpireKit.ACCENT)
		m.boxat(Vector3(0.02, 0.014, 0.78), Vector3(0, top + 0.247, 0.0), EmpireKit.GOLD)   # (the ridge)
		for sz in [-1.0, 1.0]:
			m.slab(PackedVector2Array([Vector2(-hw, 0), Vector2(hw, 0), Vector2(0, 0.075)]),
				Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, sz), Vector3(0, 1, 0)), Vector3(0, top + 0.175, sz * 0.375)), 0.01, EmpireKit.MAIN, EmpireKit.GOLD)
			m.disc(Vector3(0, top + 0.2, sz * 0.382), Vector3(0, 0, sz), Vector3.UP, 0.022, EmpireKit.ROUNDEL, 16)
		_wings(m, crescent(Vector2(0.0, 0.25), 0.5, 1.5, -0.5, 0.2, 12, 0.7), -0.02, 0.03, EmpireKit.ACCENT, EmpireKit.GOLD, 0.05)
		_marks(m, -0.58, EmpireKit.section_at(secs, -0.58)[2], 0.07, 0.0, 0.0)
		_canopy(m, g, -0.86, -0.7, 0.05, EmpireKit.section_at(secs, -0.78)[2], 0.03)
	else:
		if v == 0:   # (scythes curving forward)
			_wings(m, crescent(Vector2(0.02, -0.12), 0.56, 1.62, -0.95, 0.24, 14, 0.75), 0.0, 0.028, EmpireKit.ACCENT, EmpireKit.GOLD, 0.06)
			_wings(m, crescent(Vector2(0.02, -0.12), 0.56, 1.5, -0.6, 0.1, 12, 0.9), 0.016, 0.012, EmpireKit.MAIN, EmpireKit.MAIN, 0.06)
		else:        # (a delta, the meander along its trailing edge)
			_wings(m, PackedVector2Array([Vector2(0.08, -0.35), Vector2(0.62, 0.42), Vector2(0.56, 0.6), Vector2(0.08, 0.5)]), 0.0, 0.03, EmpireKit.ACCENT, EmpireKit.GOLD, 0.05)
			_wings(m, PackedVector2Array([Vector2(0.1, -0.2), Vector2(0.42, 0.3), Vector2(0.1, 0.3)]), 0.017, 0.012, EmpireKit.MAIN, EmpireKit.MAIN, 0.05)
			for sx in [-1.0, 1.0]:
				m.panel(Vector3(sx * 0.33, 0.034, 0.5), Vector3(0.2, 0.012 * sx, 0.03 * sx), Vector3(0, 0, 0.03), EmpireKit.FRIEZE, Vector3.UP, 6.0 / 40.0)
		_marks(m, 0.12, top, 0.09, EmpireKit.section_at(secs, 0.12)[1] + 0.003, 0.055)
		_canopy(m, g, -0.62, -0.3, 0.05, EmpireKit.section_at(secs, -0.45)[2], 0.035)
	_lamps(m, secs, -0.5, 0.5, 5)


static func _sparta(m: EmpireKit.Mesher, g: EmpireKit.Mesher, big: bool, v: int) -> void:
	var secs := _secs(big, 0.9, 0.9)
	m.loft(secs, func(seg: int, f: int) -> int:
		if f == 4:
			return EmpireKit.IRON
		if f in EmpireKit.UPPER:
			return EmpireKit.ACCENT if seg % 2 == 0 else EmpireKit.MAIN
		if f in EmpireKit.SIDES:
			return EmpireKit.IRON if seg % 2 == 0 else EmpireKit.ACCENT
		return EmpireKit.MAIN if seg % 2 == 0 else EmpireKit.IRON)
	var top: float = EmpireKit.section_at(secs, 0.15)[2]
	# The shield: eight-sided, the lambda on it.
	var sr := 0.2 if big else 0.15
	var oct := PackedVector2Array()
	for k in 8:
		oct.append(Vector2(cos(TAU * (k + 0.5) / 8.0), sin(TAU * (k + 0.5) / 8.0)) * sr + Vector2(0, 0.15))
	m.slab(oct, Transform3D(Basis.IDENTITY, Vector3(0, top + 0.012, 0)), 0.024, EmpireKit.ACCENT, EmpireKit.GOLD)
	m.disc(Vector3(0, top + 0.0245, 0.15), Vector3.UP, Vector3.FORWARD, sr * 0.8, EmpireKit.ROUNDEL, 28)
	if big:
		# A long deck forward of the shield: hazard lines, crimson magazines along it.
		m.boxat(Vector3(0.3, 0.02, 0.5), Vector3(0, EmpireKit.section_at(secs, -0.4)[2] + 0.01, -0.4), EmpireKit.IRON)
		m.boxat(Vector3(0.3, 0.004, 0.03), Vector3(0, EmpireKit.section_at(secs, -0.4)[2] + 0.022, -0.63), EmpireKit.HAZARD)
		m.boxat(Vector3(0.02, 0.004, 0.44), Vector3(0, EmpireKit.section_at(secs, -0.4)[2] + 0.022, -0.4), EmpireKit.GOLD)
		_cargo(m, 0.27, EmpireKit.ACCENT, EmpireKit.IRON, 3)
		_wings(m, PackedVector2Array([Vector2(0.15, 0.45), Vector2(0.46, 0.66), Vector2(0.46, 0.82), Vector2(0.15, 0.74)]), 0.0, 0.03, EmpireKit.ACCENT, EmpireKit.MAIN)
		_canopy(m, g, -0.88, -0.7, 0.05, EmpireKit.section_at(secs, -0.8)[2], 0.028)
	else:
		_wings(m, PackedVector2Array([Vector2(0.09, 0.0), Vector2(0.44, 0.48), Vector2(0.44, 0.72), Vector2(0.09, 0.56)]), 0.0, 0.03, EmpireKit.ACCENT, EmpireKit.MAIN)
		_wings(m, PackedVector2Array([Vector2(0.11, 0.14), Vector2(0.36, 0.5), Vector2(0.36, 0.6), Vector2(0.11, 0.42)]), 0.017, 0.012, EmpireKit.MAIN, EmpireKit.MAIN)
		if v == 1:   # (canards)
			_wings(m, PackedVector2Array([Vector2(0.06, -0.5), Vector2(0.26, -0.3), Vector2(0.26, -0.22), Vector2(0.06, -0.26)]), 0.0, 0.02, EmpireKit.MAIN, EmpireKit.ACCENT)
		_canopy(m, g, -0.6, -0.28, 0.045, EmpireKit.section_at(secs, -0.45)[2], 0.03)
	# The guns: barrels along the flanks.
	for sx in [-1.0, 1.0]:
		for k in 2:
			var x: float = sx * (0.2 + k * 0.1) if not big else sx * (0.34 + k * 0.05)
			var z := 0.25 + k * 0.12
			m.boxat(Vector3(0.04, 0.035, 0.12), Vector3(x, 0.03, z), EmpireKit.IRON)
			m.cyl(Vector3(x, 0.03, z - 0.06), Vector3(x, 0.03, z - 0.34), 0.011, 0.009, EmpireKit.STEEL, 6)
	_lamps(m, secs, -0.5, 0.4, 4, 0.0)


static func _minoa(m: EmpireKit.Mesher, g: EmpireKit.Mesher, v: int) -> void:
	var secs := _secs(false)
	_fuselage(m, secs, [EmpireKit.MAIN, EmpireKit.ACCENT, EmpireKit.MAIN, EmpireKit.ACCENT2, EmpireKit.IRON], 3, EmpireKit.ACCENT)
	var top: float = EmpireKit.section_at(secs, 0.1)[2]
	# The prow's horns: two prongs forward of the bow.
	for sx in [-1.0, 1.0]:
		m.cyl(Vector3(sx * 0.1, 0.0, -0.42), Vector3(sx * 0.085, 0.01, -0.8), 0.03, 0.02, EmpireKit.MAIN, 8)
		m.cyl(Vector3(sx * 0.085, 0.01, -0.8), Vector3(sx * 0.06, 0.03, -1.06), 0.02, 0.003, EmpireKit.ACCENT, 8)
	if v == 0:   # (the double axe: a crescent blade each side)
		_wings(m, crescent(Vector2(-0.04, 0.12), 0.5, 1.15, -1.15, 0.26, 14, 0.7, true), 0.0, 0.028, EmpireKit.MAIN, EmpireKit.ACCENT, 0.05)
		_wings(m, crescent(Vector2(-0.04, 0.12), 0.5, 0.8, -0.8, 0.12, 12, 0.8, true), 0.016, 0.012, EmpireKit.ACCENT2, EmpireKit.ACCENT2, 0.05)
	else:        # (swept blades, red tips)
		_wings(m, PackedVector2Array([Vector2(0.09, -0.1), Vector2(0.58, 0.36), Vector2(0.6, 0.58), Vector2(0.09, 0.5)]), 0.0, 0.03, EmpireKit.MAIN, EmpireKit.ACCENT, 0.05)
		_wings(m, PackedVector2Array([Vector2(0.4, 0.22), Vector2(0.58, 0.38), Vector2(0.6, 0.56), Vector2(0.4, 0.52)]), 0.017, 0.012, EmpireKit.ACCENT, EmpireKit.ACCENT, 0.05)
	_marks(m, 0.12, top, 0.095, EmpireKit.section_at(secs, 0.12)[1] + 0.003, 0.055)
	_canopy(m, g, -0.6, -0.28, 0.05, EmpireKit.section_at(secs, -0.45)[2], 0.035)
	_lamps(m, secs, -0.5, 0.5, 5)


static func _mycenae(m: EmpireKit.Mesher, g: EmpireKit.Mesher, big: bool, v: int) -> void:
	var secs := _secs(big, 1.15, 1.1)
	_fuselage(m, secs, [EmpireKit.MAIN, EmpireKit.MAIN, EmpireKit.MAIN, EmpireKit.MAIN, EmpireKit.IRON], 2, EmpireKit.ACCENT)
	var top: float = EmpireKit.section_at(secs, 0.1)[2]
	var w: float = EmpireKit.section_at(secs, 0.1)[1]
	# Gold bands round the hull; stepped blocks of stone for wings.
	for z in ([-0.55, -0.1, 0.4] if not big else [-0.62, -0.3, 0.05, 0.4]):
		var s := EmpireKit.section_at(secs, z)
		m.boxat(Vector3(float(s[1]) * 2.0 + 0.012, float(s[2]) - float(s[3]) + 0.012, 0.03), Vector3(0, (float(s[2]) + float(s[3])) * 0.5, z), EmpireKit.GOLD)
	for sx in [-1.0, 1.0]:
		for k in 3:
			var x: float = sx * (w + 0.06 + k * 0.11)
			m.boxat(Vector3(0.115, 0.1 - k * 0.022, 0.36 - k * 0.07), Vector3(x, 0.0, 0.3 + k * 0.04), EmpireKit.MAIN)
			m.boxat(Vector3(0.12, 0.012, 0.37 - k * 0.07), Vector3(x, 0.056 - k * 0.011, 0.3 + k * 0.04), EmpireKit.GOLD if k % 2 == 0 else EmpireKit.ACCENT)
		# (the boar's tusks: ivory, curving forward and in from the shoulders)
		var pts: Array = []
		for i in 7:
			var a := lerpf(0.3, 2.0, i / 6.0)
			pts.append(Vector3(sx * (w + 0.02 + 0.2 * sin(a)), 0.01, -0.3 - 0.5 * (1.0 - cos(a)) * 0.9))
		for i in 6:
			m.cyl(pts[i], pts[i + 1], lerpf(0.038, 0.006, i / 6.0), lerpf(0.038, 0.006, (i + 1) / 6.0), EmpireKit.LEATHER, 8, false)
	# The gold dome amidships, the rosette on its crown.
	var dr := 0.15 if big else 0.105
	var prof: Array = []
	for i in 6:
		var a := PI * 0.5 * i / 6.0
		prof.append([dr * cos(a), top - 0.01 + dr * 0.75 * sin(a)])
	for i in prof.size() - 1:
		m.cyl(Vector3(0, prof[i][1], 0.12), Vector3(0, prof[i + 1][1], 0.12), prof[i][0], prof[i + 1][0], EmpireKit.GOLD, 18, false)
	m.disc(Vector3(0, float(prof[5][1]) + 0.001, 0.12), Vector3.UP, Vector3.FORWARD, float(prof[5][0]), EmpireKit.ROUNDEL, 24)
	for sx in [-1.0, 1.0]:
		m.disc(Vector3(sx * (EmpireKit.section_at(secs, -0.3)[1] + 0.004), 0.0, -0.3), Vector3(sx, 0, 0), Vector3.UP, 0.05 if not big else 0.07, EmpireKit.ROUNDEL, 20)
	if big:
		_cargo(m, 0.31, EmpireKit.MAIN, EmpireKit.ACCENT, 2)
	_canopy(m, g, -0.66 if not big else -0.88, -0.36 if not big else -0.7, 0.05, EmpireKit.section_at(secs, -0.5 if not big else -0.8)[2], 0.03)
	_lamps(m, secs, -0.5, 0.5, 4 + v)


static func _ionia(m: EmpireKit.Mesher, g: EmpireKit.Mesher, big: bool, v: int) -> void:
	var secs := _secs(big, 0.95, 1.0)
	_fuselage(m, secs, [EmpireKit.MAIN, EmpireKit.ACCENT, EmpireKit.MAIN, EmpireKit.ACCENT, EmpireKit.IRON], 1, EmpireKit.GOLD)
	var top: float = EmpireKit.section_at(secs, 0.1)[2]
	# The column across the hull, a volute at each end.
	var cz := 0.3
	var half := 0.44 if not big else 0.5
	m.cyl(Vector3(-half, 0.0, cz), Vector3(half, 0.0, cz), 0.035, 0.035, EmpireKit.MAIN, 12)
	for sx in [-1.0, 1.0]:
		for k in 3:
			m.cyl(Vector3(sx * (half - 0.02 - k * 0.03), 0.0, cz), Vector3(sx * (half - 0.03 - k * 0.03), 0.0, cz), 0.04, 0.04, EmpireKit.GOLD, 12)
		m.cyl(Vector3(sx * half, -0.03, cz), Vector3(sx * half, 0.03, cz), 0.085, 0.085, EmpireKit.MAIN, 20)
		for sy in [-1.0, 1.0]:
			m.disc(Vector3(sx * half, sy * 0.031, cz), Vector3(0, sy, 0), Vector3.FORWARD, 0.078, EmpireKit.GOLD, 20)
			m.disc(Vector3(sx * half, sy * 0.032, cz), Vector3(0, sy, 0), Vector3.FORWARD, 0.058, EmpireKit.MAIN, 20)
			m.disc(Vector3(sx * half, sy * 0.033, cz), Vector3(0, sy, 0), Vector3.FORWARD, 0.036, EmpireKit.GOLD, 16)
			m.disc(Vector3(sx * half, sy * 0.034, cz), Vector3(0, sy, 0), Vector3.FORWARD, 0.016, EmpireKit.ACCENT, 12)
	# Curling wings: lapis crescents, forward from the column (v 1: and back).
	_wings(m, crescent(Vector2(0.06, -0.1), 0.4, 1.55, -0.85, 0.2, 14, 0.75), 0.004, 0.026, EmpireKit.ACCENT, EmpireKit.GOLD, 0.04)
	_wings(m, crescent(Vector2(0.06, -0.1), 0.4, 1.45, -0.5, 0.085, 12, 0.9), 0.019, 0.012, EmpireKit.MAIN, EmpireKit.MAIN, 0.04)
	if v == 1 or big:
		_wings(m, crescent(Vector2(0.1, 0.45), 0.36, -1.4, 0.7, 0.16, 12, 0.75), -0.004, 0.024, EmpireKit.ACCENT, EmpireKit.GOLD, 0.03)
	if big:
		_cargo(m, 0.29, EmpireKit.MAIN, EmpireKit.ACCENT, 2)
	_marks(m, -0.02, EmpireKit.section_at(secs, -0.02)[2], 0.085 if not big else 0.12, EmpireKit.section_at(secs, -0.02)[1] + 0.003, 0.05)
	_canopy(m, g, -0.64 if not big else -0.88, -0.32 if not big else -0.7, 0.05, EmpireKit.section_at(secs, -0.48 if not big else -0.8)[2], 0.034)
	_lamps(m, secs, -0.5, 0.2, 4)


static func _cyclades(m: EmpireKit.Mesher, g: EmpireKit.Mesher, big: bool, v: int) -> void:
	# One smooth piece: an oval hull, fuller for the traders.
	var k := 1.35 if big else 1.0
	var secs := [[-1.0, 0.004, 0.004, 0.0], [-0.86, 0.045 * k, 0.035 * k, 0.0], [-0.55, 0.1 * k, 0.07 * k, 0.0], [-0.1, 0.14 * k, 0.09 * k, 0.0],
		[0.35, 0.145 * k, 0.09 * k, 0.0], [0.62, 0.12 * k, 0.075 * k, 0.0], [0.8, 0.085 * k, 0.055 * k, 0.0]]
	m.round_loft(secs, 14, func(seg: int, i: int) -> int:
		if i >= 8 and i <= 12:
			return EmpireKit.MAIN if seg != 3 else EmpireKit.ACCENT   # (the belly)
		return EmpireKit.MAIN)
	# A blue line along each flank, a terracotta one over it.
	for sx in [-1.0, 1.0]:
		for q in 8:
			var z0 := -0.7 + q * 0.17
			var a := EmpireKit.section_at([[-1.0, 0.004], [-0.86, 0.045 * k], [-0.55, 0.1 * k], [-0.1, 0.14 * k], [0.35, 0.145 * k], [0.62, 0.12 * k], [0.8, 0.085 * k]].map(
				func(s): return [s[0], s[1], 0.0, 0.0, 0.0]), z0 + 0.085)
			m.boxat(Vector3(0.006, 0.01, 0.16), Vector3(sx * (float(a[1]) * 0.985), 0.012, z0 + 0.085), EmpireKit.ACCENT)
			m.boxat(Vector3(0.006, 0.006, 0.16), Vector3(sx * (float(a[1]) * 0.94), 0.03, z0 + 0.085), EmpireKit.ACCENT2)
	# The prow: curled up and back over the bow.
	var pts: Array = []
	for i in 9:
		var a := lerpf(-0.4, 3.6, i / 8.0)
		pts.append(Vector3(0, 0.05 + 0.075 * (1.0 - cos(a)) * (1.0 - i * 0.035), -0.93 + 0.075 * sin(a) * (1.0 - i * 0.05)))
	for i in 8:
		m.cyl(pts[i], pts[i + 1], lerpf(0.024, 0.008, i / 8.0), lerpf(0.024, 0.008, (i + 1) / 8.0), EmpireKit.MAIN, 8, false)
	# Its oars: ribs out from the flanks, swept back.
	var ribs := 5 if not big else 6
	for r in ribs:
		var z := -0.42 + r * (0.2 if not big else 0.18)
		var len := (0.3 + 0.1 * sin(PI * (r + 0.5) / ribs)) * (1.0 if v == 0 else 0.8)
		_wings(m, crescent(Vector2(0.1 * k, z + 0.34), 0.34, -1.5, -1.5 + len * 2.4, 0.07, 8, 0.8), -0.01, 0.014, EmpireKit.MAIN, EmpireKit.ACCENT if r % 2 == 0 else EmpireKit.MAIN, -0.05)
	# The spiral on its back.
	var top := 0.09 * k
	m.cyl(Vector3(0, top - 0.03, 0.12), Vector3(0, top + 0.004, 0.12), 0.125 * k, 0.115 * k, EmpireKit.MAIN, 24)
	m.disc(Vector3(0, top + 0.005, 0.12), Vector3.UP, Vector3.FORWARD, 0.108 * k, EmpireKit.ROUNDEL, 28)
	var cs := [[-0.62, 0.018 * k, 0.07 * k, -0.01, 0.01], [-0.48, 0.045 * k, 0.1 * k, -0.01, 0.02], [-0.3, 0.035 * k, 0.095 * k, -0.01, 0.015]]
	g.loft(cs, func(_s: int, _f: int) -> int: return 0)


static func _pirates(m: EmpireKit.Mesher, g: EmpireKit.Mesher, big: bool, v: int) -> void:
	var secs := _secs(big, 1.0, 0.95)
	m.loft(secs, func(seg: int, f: int) -> int:
		if f == 4:
			return EmpireKit.IRON
		if f in EmpireKit.UPPER:
			return EmpireKit.ACCENT if seg in [1, 3] else EmpireKit.MAIN
		return EmpireKit.MAIN if (seg + f) % 3 else EmpireKit.IRON)
	var top: float = EmpireKit.section_at(secs, 0.1)[2]
	# Scythes forward, bone at their edges; a second pair back on the raiders' other kind.
	_wings(m, crescent(Vector2(0.0, -0.1), 0.52, 1.6, -1.05, 0.24, 14, 0.7), 0.0, 0.028, EmpireKit.ACCENT, EmpireKit.ACCENT2, 0.05)
	_wings(m, crescent(Vector2(0.0, -0.1), 0.52, 1.5, -0.7, 0.09, 12, 0.9), 0.016, 0.012, EmpireKit.IRON, EmpireKit.IRON, 0.05)
	if v == 1 or big:
		_wings(m, crescent(Vector2(0.05, 0.5), 0.38, -1.5, 0.9, 0.18, 12, 0.7), -0.004, 0.024, EmpireKit.ACCENT, EmpireKit.ACCENT2, -0.03)
	# Bone: a ram at the bow, spikes down the spine and off the flanks.
	m.cyl(Vector3(0, -0.01, -0.86), Vector3(0, -0.02, -1.14), 0.03, 0.002, EmpireKit.ACCENT2, 8)
	for i in 5:
		var z := -0.5 + i * 0.24
		var s := EmpireKit.section_at(secs, z)
		m.cyl(Vector3(0, float(s[2]) - 0.01, z), Vector3(0, float(s[2]) + 0.09 + 0.02 * (i % 2), z + 0.06), 0.022, 0.002, EmpireKit.ACCENT2, 6)
		for sx in [-1.0, 1.0]:
			m.cyl(Vector3(sx * (float(s[1]) - 0.01), -0.02, z), Vector3(sx * (float(s[1]) + 0.1), -0.05, z + 0.08), 0.018, 0.002, EmpireKit.ACCENT2, 6)
	# A tattered red sail on a mast aft, the skull on it; the skull on the hull.
	var mast_z := 0.42
	m.cyl(Vector3(0, top - 0.01, mast_z), Vector3(0, top + 0.42, mast_z + 0.05), 0.012, 0.008, EmpireKit.IRON, 6)
	var sail := PackedVector2Array([Vector2(0.0, 0.4), Vector2(0.36, 0.38), Vector2(0.4, 0.16), Vector2(0.33, 0.2), Vector2(0.3, 0.08), Vector2(0.24, 0.17),
		Vector2(0.19, 0.05), Vector2(0.13, 0.15), Vector2(0.07, 0.07), Vector2(0.0, 0.14)])
	m.slab(sail, Transform3D(Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)), Vector3(0, top, mast_z + 0.03)), 0.008, EmpireKit.ACCENT, EmpireKit.ACCENT)
	for sx in [-1.0, 1.0]:
		m.disc(Vector3(sx * 0.0055, top + 0.28, mast_z + 0.2), Vector3(sx, 0, 0), Vector3.UP, 0.085, EmpireKit.ROUNDEL, 20)
	_marks(m, -0.05, EmpireKit.section_at(secs, -0.05)[2], 0.085 if not big else 0.12, EmpireKit.section_at(secs, -0.05)[1] + 0.003, 0.05)
	if big:
		_cargo(m, 0.3, EmpireKit.IRON, EmpireKit.ACCENT, 2)
	_canopy(m, g, -0.64 if not big else -0.88, -0.36 if not big else -0.72, 0.045, EmpireKit.section_at(secs, -0.5 if not big else -0.8)[2], 0.028)
	_lamps(m, secs, -0.5, 0.4, 4, -0.005)


static func _plain(m: EmpireKit.Mesher, g: EmpireKit.Mesher, big: bool, v: int) -> void:
	var secs := _secs(big)
	_fuselage(m, secs, [EmpireKit.MAIN, EmpireKit.MAIN, EmpireKit.MAIN, EmpireKit.IRON, EmpireKit.IRON], 2, EmpireKit.ACCENT)
	var top: float = EmpireKit.section_at(secs, 0.1)[2]
	if big:
		_cargo(m, 0.3, EmpireKit.MAIN, EmpireKit.IRON, 3)
		_wings(m, PackedVector2Array([Vector2(0.16, 0.5), Vector2(0.44, 0.62), Vector2(0.44, 0.8), Vector2(0.16, 0.78)]), 0.0, 0.03, EmpireKit.MAIN, EmpireKit.ACCENT)
	else:
		_wings(m, PackedVector2Array([Vector2(0.09, -0.05 - 0.1 * v), Vector2(0.5, 0.4), Vector2(0.5, 0.62), Vector2(0.09, 0.55)]), 0.0, 0.03, EmpireKit.MAIN, EmpireKit.ACCENT, 0.04)
		for sx in [-1.0, 1.0]:
			m.box(Vector3(0.012, 0.2, 0.2), Transform3D(Basis(Vector3(0, 0, 1), -sx * 0.4), Vector3(sx * 0.1, top + 0.08, 0.55)), EmpireKit.ACCENT)
	_marks(m, 0.1, top, 0.07, EmpireKit.section_at(secs, 0.1)[1] + 0.003, 0.045)
	_canopy(m, g, -0.62 if not big else -0.88, -0.3 if not big else -0.7, 0.05, EmpireKit.section_at(secs, -0.45 if not big else -0.8)[2], 0.034)
	_lamps(m, secs, -0.5, 0.5, 5)
