class_name CosmosNpcInterior
extends Node3D
## A trader's insides, walkable - made when you come near one down in a port
## (on a worker), fitted to its hull: the hull sliced across every metre, each
## slice's room as wide and as high as the hull leaves there (a little in from
## its skin; not out into the engine pods beside it), from the door at the top
## of its stern ramp forward as far as there's room to stand. The cargo hold aft
## (crates along its sides), the crew's quarters (bunks), the bridge at the
## front (consoles, the pilot's seat). A doorway cut in the hull over the ramp
## while it's down (EmpireKit.cut_mat). A deck for the walker as
## CosmosShipInterior's and CosmosHangar's are: floor_y, ceiling_y, confine.
## In the ship's own space (a child of it, unmoved).

const SLICE := 1.0
const DOOR_HW := 0.8          # the doorways between rooms (half width)
const DOOR_H := 2.3
const MAX_HW := 5.5
const HEAD := 3.0             # its rooms' height at most

var ship: Node3D
var emp := ""
var built := false
var ok := false               # (rooms fitted - a hull too slight for any: no way in)
var sill := 0.0               # the floor (the ramp's top)
var z_aft := 0.0              # the door, at the ramp's hinge
var z_fore := 0.0
var z0 := 0.0                 # slice 0's aft... its fore edge (hws[i]: [z0 + i, z0 + i + 1])
var hws: Array = []
var ceils: Array = []
var walls: Array = []         # the rooms' partitions (z)
var rooms: Array = []         # [name, z fore, z aft]
var blocks: Array = []        # furniture: [x0, z0, x1, z1]
var seat_pos := Vector3.INF   # the passenger seat beside the pilot's (its sitting point), if there's room for one
var seat := {"face": Vector3(0, 0, -1), "kind": "sit", "who": null}   # (the walker's seat: facing the nose)
var pilot_pos := Vector3.INF  # the pilot's seat at the consoles (its sitting point) - its own pilot's, never the walker's
var pilot_seat := {"face": Vector3(0, 0, -1), "kind": "sit", "who": null}
var ramp_hw := 1.2
var foot := Vector3.ZERO      # the ramp's foot (ship space)
var ramp_lift := 0.1          # the ramp's top face over its middle line (its plank's half thickness, along its slope)
var door := AABB()            # the doorway through the hull (ship space: its solid's - CosmosHullGrid - cut out while the ramp's down)
var _cut_lo := Vector3.ZERO   # the doorway in the hull (its mesh's space)
var _cut_hi := Vector3.ZERO
var _hull: MeshInstance3D
var _task := -1
var _out := {}
var _lights: Array = []
var _light_t := 0.0


func setup(s: Node3D, e: String) -> void:
	ship = s
	emp = e
	name = "Interior"
	var rng = s.get("_rng")   # (the Live Editor's edits: this hull - its kind and seed shape the rooms)
	set_meta("edit_key", "interior/%s/%s/%d" % [e, str(s.get("hull_kind")), int(rng.seed) if rng is RandomNumberGenerator else 0])
	for mi: MeshInstance3D in s.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh and mi.mesh.has_meta("verts"):
			_hull = mi
			break
	var ramp: Node3D = s.get("_ramp")
	if _hull == null or ramp == null:
		built = true
		return
	var hb: AABB = s.call("_hull_box")
	var plank: Node3D = ramp.get_child(0)
	ramp_hw = plank.scale.x * 0.5
	var ang: float = s.get("_ramp_ang")
	foot = ramp.position + Vector3(0, -sin(ang), cos(ang)) * float(s.get("_ramp_len"))
	sill = ramp.position.y + plank.scale.y * 0.5   # (the ramp's top face at its hinge)
	ramp_lift = plank.scale.y * 0.5 / maxf(cos(ang), 0.2)
	z_aft = ramp.position.z
	var xf := _to_ship(_hull)
	var args := [_hull.mesh.get_meta("verts"), xf, hb, sill, z_aft, ramp_hw]
	_task = Jobs.add(func(): _out = _make(args), false, "trader interior")


func _to_ship(n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var at: Node = n
	while at != ship and at != null:
		xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf


func _exit_tree() -> void:
	if _task >= 0:
		Jobs.wait(_task)
		_task = -1


func _process(delta: float) -> void:
	if _task >= 0:
		if not Jobs.done(_task):
			return
		Jobs.wait(_task)
		_task = -1
		_finish()
	_light_t -= delta
	if _light_t <= 0.0 and not _lights.is_empty():   # (its lamps lit only with you aboard - from outside, their strips glow through the door)
		_light_t = 0.25
		var c: Node = ship.get("cosmos") if ship else null
		var w: Node = c.get("walker") if c else null
		var aboard: bool = w != null and w.get("deck") == self
		for o: OmniLight3D in _lights:
			o.visible = aboard


func _finish() -> void:
	built = true
	if _out.is_empty():
		return
	ok = true
	for k in ["z_fore", "z0", "hws", "ceils", "walls", "rooms", "blocks"]:
		set(k, _out[k])
	SolidsEdit.installed(self)   # (its furniture as edited in the Live Editor, if it was)
	seat_pos = _out.get("seat", Vector3.INF)
	pilot_pos = _out.get("pilot", Vector3.INF)
	var tunnel: float = _out["tunnel"]
	var mi := MeshInstance3D.new()
	mi.name = "Rooms"
	mi.mesh = _out["mesh"]
	mi.material_override = EmpireKit.mat("inside", emp)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	for r in rooms:
		var o := OmniLight3D.new()
		var zm := (float(r[1]) + float(r[2])) * 0.5
		o.position = Vector3(0, _ceil_at(zm) - 0.35, zm)
		o.omni_range = maxf(float(r[2]) - float(r[1]), 6.0)
		o.omni_attenuation = 0.9
		o.light_energy = 1.3
		o.light_color = Color(1.0, 0.86, 0.68) if r[0] != "Bridge" else Color(0.85, 0.92, 1.0)
		o.shadow_enabled = false
		o.visible = false
		add_child(o)
		_lights.append(o)
	# The doorway through the hull: over the ramp's top, from the rooms' aft end out past the stern.
	var inv := _to_ship(_hull).affine_inverse()
	var lo := Vector3(-ramp_hw - 0.05, sill - 0.4, tunnel - 0.4)
	var hi := Vector3(ramp_hw + 0.05, sill + DOOR_H + 0.25, z_aft + 40.0)
	door = AABB(lo, hi - lo)
	var a := inv * lo
	var b := inv * hi
	_cut_lo = Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	_cut_hi = Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	add_to_group("cam_solid")   # (its walls between rooms stop the camera - aboard: cam_hit)
	set_meta("cam_reach", 120.0)
	if _hull.material_override is ShaderMaterial:
		_hull.material_override = EmpireKit.cut_mat(_hull.material_override)
	set_cut(true)


## The doorway open in the hull (the ramp down) or not (it's shut: the hull whole).
func set_cut(open: bool) -> void:
	if _hull == null or not ok:
		return
	_hull.set_instance_shader_parameter("cut_lo", _cut_lo if open else Vector3.ZERO)
	_hull.set_instance_shader_parameter("cut_hi", _cut_hi if open else Vector3.ZERO)


# --- The walker's deck --------------------------------------------------------------------

func _slice(z: float) -> int:
	return clampi(int(floor((z - z0) / SLICE)), 0, hws.size() - 1)


func _hw_at(z: float, m := 0.0) -> float:
	return minf(float(hws[_slice(z - m)]), float(hws[_slice(z + m)]))


func _ceil_at(z: float) -> float:
	return float(ceils[_slice(z)])


## Off the ship, at `l` (its space): stepping onto its ramp - over it, no lower than
## a step under its top face (from its foot, or from the side where it's low).
func steps_on(l: Vector3) -> bool:
	if not ok or not ramp_open() or absf(l.x) > ramp_hw or l.z < z_aft or l.z > foot.z + 0.8:
		return false
	var f := floor_y(Vector3(0, 0, minf(l.z, foot.z)))
	return l.y > f - 0.7 and l.y < f + 1.5


func on_ramp(l: Vector3) -> bool:
	return l.z > z_aft and ramp_open()


## Its ramp down (in port): the door at its top open.
func ramp_open() -> bool:
	return ship != null and float(ship.get("_ramp_k")) > 0.5


func floor_y(l: Vector3) -> float:
	if on_ramp(l):
		return lerpf(sill, foot.y + ramp_lift, clampf((l.z - z_aft) / maxf(foot.z - z_aft, 0.1), 0.0, 1.0))   # (its top face, not its middle)
	return sill


func ceiling_y(l: Vector3) -> float:
	if on_ramp(l) or not ok:
		return floor_y(l) + 3.2
	return _ceil_at(l.z)


## `l` kept within its rooms (and on the ramp), `m` in from their walls and things.
func confine(l: Vector3, m: float) -> Vector3:
	if not ok:
		return l
	var p := l
	if not ramp_open():
		p.z = minf(p.z, z_aft - m)   # (its ramp up: the door shut behind you)
	elif p.z > z_aft:   # (the ramp: down to its foot - off it, Cosmos puts you on the port's floor)
		p.x = clampf(p.x, -ramp_hw + m, ramp_hw - m)
		p.z = minf(p.z, foot.z + 0.6)
		return p
	p.z = maxf(p.z, z_fore + m)
	if p.z > z_aft - m and absf(p.x) > ramp_hw - m:   # (the aft wall, either side of the door)
		p.z = z_aft - m
	for wz: float in walls:   # (the partitions: through their doorways only)
		if absf(p.z - wz) < m + 0.1 and absf(p.x) > DOOR_HW - m:
			p.z = wz + (m + 0.1) * (1.0 if p.z > wz else -1.0)
	var hw := _hw_at(p.z, m)   # (its width where it ends up along the ship)
	p.x = clampf(p.x, -hw + m, hw - m)
	for b in blocks:
		var x0: float = b[0] - m
		var zz0: float = b[1] - m
		var x1: float = b[2] + m
		var zz1: float = b[3] + m
		if p.x > x0 and p.x < x1 and p.z > zz0 and p.z < zz1:
			var opts := [[p.x - x0, Vector3(x0, p.y, p.z)], [x1 - p.x, Vector3(x1, p.y, p.z)],
				[p.z - zz0, Vector3(p.x, p.y, zz0)], [zz1 - p.z, Vector3(p.x, p.y, zz1)]]
			opts.sort_custom(func(a, c): return a[0] < c[0])
			p = opts[0][1]
	p.x = clampf(p.x, -hw + m, hw - m)   # (never out through a wall, pushed off a thing)
	return p


## The camera's ray (`o`, `dir`, world) stopped short of the walls across its
## rooms - outside their doorways - while you're aboard (else nothing here).
func cam_hit(o: Vector3, dir: Vector3, limit: float) -> float:
	var c: Node = ship.get("cosmos") if ship else null
	var w: Node = c.get("walker") if c else null
	if w == null or w.get("deck") != self or (c.get("cam") and c.cam.walker == null):
		return INF   # (not aboard - or in the passenger seat, looking at it from outside)
	var lo := to_local(o)
	var ld := global_basis.inverse() * dir
	if absf(ld.z) < 1e-5:
		return INF
	var best := INF
	var across: Array = walls.duplicate()
	across.append(z_aft)
	for wz: float in across:
		var t := (wz - lo.z) / ld.z
		if t <= 0.0 or t > limit:
			continue
		var p := lo + ld * t
		var dhw := ramp_hw if is_equal_approx(wz, z_aft) else DOOR_HW
		if absf(p.x) > dhw - 0.15 or p.y > sill + DOOR_H - 0.15:
			best = minf(best, t)
	return maxf(best - 0.25, 0.2) if best < INF else INF


## Where you are aboard: its room's name.
func room_at(l: Vector3) -> String:
	if on_ramp(l):
		return "the ramp"
	for r in rooms:
		if l.z >= float(r[1]) and l.z <= float(r[2]):
			return str(r[0]).to_lower()
	return "the corridor"


# --- Made on a worker: the layout and the mesh ------------------------------------------

static func _make(args: Array) -> Dictionary:
	var src: PackedVector3Array = args[0]
	var xf: Transform3D = args[1]
	var hb: AABB = args[2]
	var sill: float = args[3]
	var z_aft: float = args[4]
	var rhw: float = args[5]
	var zs := hb.position.z
	var n := int(ceil((z_aft - zs) / SLICE))
	if n < 5:
		return {}
	# Each slice's cross-section through its middle: the hull's triangles cut by
	# that plane, the cut lines sampled every 0.4 m - as (|x|, y) points.
	var sec: Array = []
	for i in n:
		sec.append(PackedVector2Array())
	var k := 0
	while k + 2 < src.size():
		var a: Vector3 = xf * src[k]
		var b: Vector3 = xf * src[k + 1]
		var c: Vector3 = xf * src[k + 2]
		k += 3
		var lo := minf(a.z, minf(b.z, c.z))
		var hi := maxf(a.z, maxf(b.z, c.z))
		var i0 := maxi(int(ceil((lo - zs) / SLICE - 0.5)), 0)
		var i1 := mini(int(floor((hi - zs) / SLICE - 0.5)), n - 1)
		for i in range(i0, i1 + 1):
			var zm := zs + (i + 0.5) * SLICE
			var cut: Array = []
			for e in [[a, b], [b, c], [c, a]]:
				var p: Vector3 = e[0]
				var q: Vector3 = e[1]
				if (p.z - zm) * (q.z - zm) <= 0.0 and absf(q.z - p.z) > 1e-6:
					cut.append(p.lerp(q, (zm - p.z) / (q.z - p.z)))
			if cut.size() >= 2:
				var p0: Vector3 = cut[0]
				var p1: Vector3 = cut[1]
				var steps := maxi(1, int(p0.distance_to(p1) / 0.4))
				for st in steps + 1:
					var p := p0.lerp(p1, float(st) / steps)
					sec[i].append(Vector2(absf(p.x), p.y))
	# The rooms' width (to the nearest skin at standing height, a little in from it) and
	# height (to the lowest skin over them) per slice - standing room where there's enough,
	# and the hull closed under its floor.
	var hw: Array = []
	var ce: Array = []
	var good: Array = []
	for i in n:
		var pts: PackedVector2Array = sec[i]
		var near := INF
		for p in pts:
			if p.y > sill + 0.1 and p.y < sill + 2.2:
				near = minf(near, p.x)
		var w := snappedf(minf(near - 0.4, MAX_HW), 0.1) if near < INF else 0.0
		var over := INF
		var belly := false
		for p in pts:
			if p.x <= w + 0.2:
				if p.y > sill + 0.5:
					over = minf(over, p.y)
				elif p.y < sill - 0.05:
					belly = true
		var c := minf(sill + HEAD, over - 0.3)
		hw.append(w)
		ce.append(c)
		good.append(w >= 0.85 and c - sill >= 2.2 and belly)
	# The rooms: the longest stretch with standing room that reaches near the stern;
	# from its aft end to the door a corridor (through whatever's there: the doorway
	# cut in the hull runs its length).
	var max_skip := maxi(7, int(n * 0.4))
	var best := [-1, -1]
	var j := 0
	while j < n:
		if not good[j]:
			j += 1
			continue
		var e := j
		while e + 1 < n and good[e + 1]:
			e += 1
		if e >= n - 1 - max_skip and e - j + 1 >= 5 and (best[0] < 0 or e - j > int(best[1]) - int(best[0])):
			best = [j, e]
		j = e + 1
	if best[0] < 0:
		return {}
	var i_fore: int = best[0]
	var i_aft: int = best[1]
	for i in range(i_aft + 1, n):   # (the passage: as wide as the ramp, door high)
		hw[i] = maxf(rhw + 0.15, 0.85)
		ce[i] = sill + DOOR_H + 0.15
	var z_fore := zs + i_fore * SLICE
	var tunnel := minf(zs + (i_aft + 1) * SLICE, z_aft)
	var hws := hw.slice(i_fore)
	var ceils := ce.slice(i_fore)
	# The rooms: the hold aft, the quarters, the bridge at the front.
	var L := tunnel - z_fore
	var rooms: Array = []
	if L < 7.0:
		rooms = [["Cabin", z_fore, tunnel]]
	elif L < 14.0:
		rooms = [["Bridge", z_fore, z_fore + L * 0.45], ["Cargo hold", z_fore + L * 0.45, tunnel]]
	else:
		rooms = [["Bridge", z_fore, z_fore + L * 0.28], ["Crew quarters", z_fore + L * 0.28, z_fore + L * 0.6], ["Cargo hold", z_fore + L * 0.6, tunnel]]
	var walls: Array = []
	for r in rooms.slice(1):
		walls.append(snappedf(float(r[1]), 0.01))
	if tunnel < z_aft - 0.5:   # (a passage through the tail: a door at its fore end too)
		walls.append(tunnel)
	var lay := {"z_fore": z_fore, "z0": z_fore, "hws": hws, "ceils": ceils, "walls": walls, "rooms": rooms, "blocks": [], "tunnel": tunnel}
	lay["mesh"] = _mesh(lay, sill, z_aft, rhw)
	return lay


## Unknown entries (`gap`) from their nearest known neighbour.
static func _fill(a: Array, gap := -1.0) -> void:
	for i in a.size():
		if a[i] != gap:
			continue
		for d in range(1, a.size()):
			if i - d >= 0 and a[i - d] != gap:
				a[i] = a[i - d]
				break
			if i + d < a.size() and a[i + d] != gap:
				a[i] = a[i + d]
				break


static func _mesh(lay: Dictionary, sill: float, z_aft: float, rhw: float) -> ArrayMesh:
	var m := EmpireKit.Mesher.new()
	var hws: Array = lay["hws"]
	var ceils: Array = lay["ceils"]
	var z0: float = lay["z0"]
	var blocks: Array = lay["blocks"]
	var wall := EmpireKit.MAIN
	var n := hws.size()
	for i in n:
		var za := z0 + i * SLICE
		var zb := minf(za + SLICE, z_aft)
		if zb <= za:
			break
		var w: float = hws[i]
		var c: float = ceils[i]
		var mid := (za + zb) * 0.5
		var len := zb - za
		m.boxat(Vector3(w * 2.0 + 0.24, 0.12, len), Vector3(0, sill - 0.06, mid), EmpireKit.STEEL)
		m.boxat(Vector3(w * 2.0 + 0.24, 0.12, len), Vector3(0, c + 0.06, mid), EmpireKit.IRON)
		for sx in [-1.0, 1.0]:
			m.boxat(Vector3(0.12, c - sill, len), Vector3(sx * (w + 0.06), (sill + c) * 0.5, mid), wall)
			m.boxat(Vector3(0.05, 0.08, len), Vector3(sx * (w - 0.02), sill + 0.9, mid), EmpireKit.ACCENT)   # (a rail along its walls)
		if i % 2 == 0:
			m.boxat(Vector3(0.24, 0.04, len * 0.8), Vector3(0, c - 0.02, mid), EmpireKit.LAMP)
		if i + 1 < n:   # (steps in the walls and the ceiling where the hull narrows)
			var w2: float = hws[i + 1]
			var c2: float = ceils[i + 1]
			if absf(w2 - w) > 0.01:
				var lo := minf(w, w2)
				var hi := maxf(w, w2)
				for sx in [-1.0, 1.0]:
					m.boxat(Vector3(hi - lo + 0.12, maxf(c, c2) - sill, 0.12), Vector3(sx * (lo + hi) * 0.5, (sill + maxf(c, c2)) * 0.5, zb), wall)
			if absf(c2 - c) > 0.01:
				m.boxat(Vector3(minf(w, w2) * 2.0, absf(c2 - c) + 0.12, 0.12), Vector3(0, (c + c2) * 0.5, zb), EmpireKit.IRON)
	# The fore wall; the aft one round the door; the partitions with their doorways.
	var zf: float = lay["z_fore"]
	m.boxat(Vector3(float(hws[0]) * 2.0 + 0.24, float(ceils[0]) - sill, 0.12), Vector3(0, (sill + float(ceils[0])) * 0.5, zf - 0.06), wall)
	_door_wall(m, z_aft, float(hws[n - 1]), float(ceils[n - 1]), sill, rhw, wall)
	for wz: float in lay["walls"]:
		var i := clampi(int(floor((wz - z0) / SLICE)), 0, n - 1)
		_door_wall(m, wz, float(hws[i]), float(ceils[i]), sill, DOOR_HW, wall)
	# Their furniture.
	for r in lay["rooms"]:
		var ra: float = r[1]
		var rb: float = r[2]
		match str(r[0]):
			"Bridge":
				var w: float = hws[clampi(int((ra + 1.5 - z0) / SLICE), 0, n - 1)]
				var cw := minf(w * 2.0 - 0.6, 3.2)
				m.boxat(Vector3(cw, 1.0, 0.6), Vector3(0, sill + 0.5, ra + 0.4), EmpireKit.STEEL)
				m.boxat(Vector3(cw + 0.04, 0.06, 0.64), Vector3(0, sill + 1.03, ra + 0.4), EmpireKit.IRON)
				m.panel(Vector3(0, sill + 1.45, ra + 0.2), Vector3(cw * 0.4, 0, 0), Vector3(0, -0.35, 0.1), EmpireKit.SCREEN, Vector3(0, 0.3, 1))
				blocks.append([-cw * 0.5, ra, cw * 0.5, ra + 0.75])
				CosmosShipInterior._chair(m, Vector3(0, sill, ra + 1.9), 0.85, true)
				blocks.append([-0.5, ra + 1.4, 0.5, ra + 2.4])
				lay["pilot"] = Vector3(0, sill, ra + 1.92)   # (its pilot's: CosmosNpc.board_ride walks him to it)
				if w >= 2.1:   # (the passenger seat beside it)
					CosmosShipInterior._chair(m, Vector3(1.35, sill, ra + 1.9), 0.85)
					lay["seat"] = Vector3(1.35, sill, ra + 1.92)
				if w >= 1.8 and rb - ra > 4.5:
					for sx in [-1.0, 1.0]:
						CosmosShipInterior._console(m, Vector3(sx * (w - 0.45), sill, ra + 3.2), sx)
						blocks.append([sx * (w - 0.45) - 0.45, ra + 2.45, sx * (w - 0.45) + 0.45, ra + 3.95])
			"Crew quarters":
				var z := ra + 0.4
				while z + 2.1 < rb - 0.4:
					var w: float = minf(float(hws[clampi(int((z - z0) / SLICE), 0, n - 1)]), float(hws[clampi(int((z + 2.0 - z0) / SLICE), 0, n - 1)]))
					if w >= 1.8:
						for sx in [-1.0, 1.0]:
							var x: float = sx * (w - 0.5)
							for tier in [0.45, 1.45]:
								m.boxat(Vector3(0.9, 0.3, 2.0), Vector3(x, sill + tier, z + 1.0), EmpireKit.STEEL)
								m.boxat(Vector3(0.84, 0.14, 1.9), Vector3(x, sill + tier + 0.22, z + 1.0), EmpireKit.LEATHER)
								m.boxat(Vector3(0.5, 0.12, 0.36), Vector3(x, sill + tier + 0.34, z + 0.25), EmpireKit.CLOTH)
							m.boxat(Vector3(0.9, 2.0, 0.08), Vector3(x, sill + 1.0, z), EmpireKit.STEEL)
							blocks.append([x - 0.45, z - 0.05, x + 0.45, z + 2.0])
					z += 2.4
			_:   # (the hold - a cabin too: crates along its sides)
				var z := rb - 1.0
				var k := 0
				while z > ra + 0.9:
					var w: float = float(hws[clampi(int((z - z0) / SLICE), 0, n - 1)])
					if w >= 2.0:
						for sx in [-1.0, 1.0]:
							var x: float = sx * (w - 0.65)
							var h := 1.0 + 0.15 * float((k + int(sx)) % 3)
							EmpireKit.crate(m, Vector3(x, sill, z), Vector3(1.1, h, 1.2), (k + int(sx)) % 4 == 0)
							if float(ceils[clampi(int((z - z0) / SLICE), 0, n - 1)]) - sill > 2.8 and k % 2 == 0:
								EmpireKit.crate(m, Vector3(x, sill + h, z), Vector3(1.0, 0.9, 1.1), false, 0.15)
							blocks.append([x - 0.6, z - 0.65, x + 0.6, z + 0.65])
					z -= 1.5
					k += 1
	return m.commit()


## A wall across at `z` with a doorway `dhw` wide (half) in its middle, a lintel over it, a frame round it.
static func _door_wall(m: EmpireKit.Mesher, z: float, hw: float, c: float, sill: float, dhw: float, wall: int) -> void:
	var side := hw - dhw
	if side > 0.02:
		for sx in [-1.0, 1.0]:
			m.boxat(Vector3(side, c - sill, 0.12), Vector3(sx * (dhw + side * 0.5), (sill + c) * 0.5, z), wall)
	var top := minf(sill + DOOR_H, c)
	if c - top > 0.02:
		m.boxat(Vector3(dhw * 2.0, c - top, 0.12), Vector3(0, (top + c) * 0.5, z), wall)
	for sx in [-1.0, 1.0]:   # (the frame)
		m.boxat(Vector3(0.1, top - sill, 0.2), Vector3(sx * (dhw + 0.05), (sill + top) * 0.5, z), EmpireKit.STEEL)
	m.boxat(Vector3(dhw * 2.0 + 0.2, 0.1, 0.2), Vector3(0, top - 0.05, z), EmpireKit.STEEL)
