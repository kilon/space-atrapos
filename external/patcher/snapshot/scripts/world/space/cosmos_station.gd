class_name CosmosStation
extends Node3D
## A space station (the 3D game): big - ~2.5 km across - each empire's its own
## design, from its reference sheet (_minoan, _athens, _sparta, _mycenae,
## _ionia, _cyclades, _pirates; the independents': _plain - a tower, a ring,
## solar wings) in the empire's look (EmpireKit): a ring, a hub with the
## emblem, spokes, four platforms of landing pads out from the ring (numbered,
## lit; two big ones for the largest freighters), each pad a lift down a lit
## shaft closed by sliding shutters. Docking is flown by hand: ask for a pad
## (Cosmos.request_dock), fly to it, set down on it - its lift takes the ship
## into the hangar. Other ships use the pads too (CosmosNpcShip).
## Its solid parts are boxes and cylinders, kept as data (Part: ~500 a
## station - no nodes): the camera and the ships bump into the parts
## themselves (push_out, cam_hit), and a worker bakes them, with the drawn-only
## decoration (columns, friezes, banners, roundels, rails - recorded as it's
## laid out: Dress), into one mesh (_bake).

const PAD_SMALL := 90.0        # m across: ships up to ~70 m
const PAD_LARGE := 230.0       # the big freighters

var record := {}
var reach := 1300.0            # (the HUD, clearances)
var bay := Vector3.ZERO        # (kept for old callers: the first pad)
## The pads: [{id, at (local, its top's middle), size, owner (a node or null), label}]
var pads: Array = []
var _ring: Node3D              # (kept for the solids' maths: nothing turns)
var _mats := {}
## The parts ships bump into: [in the ring?, centre, bound, inverse transform, half size, cylinder?, basis]
var _solids: Array = []
var _bound := 0.0
var _parts: Array = []         # Part: every box and cylinder of it
## Its landing platforms - each over a port (a hangar module under it: CosmosHangar):
## [{centre, yaw, pd (deep, outward), pw (wide, along its pads), big, pads: [ids]}]
var platforms: Array = []
## The port module's numbers (platform space: x out, z along its pads, y up from the platform's middle).
const PORT_FLOOR := 12.4 - 60.0        # the port's floor: a pad's top, LIFT_DEPTH down (= Cosmos.LIFT_DEPTH)
const PORT_CEIL := -14.0               # its hall's ceiling (the platform's underside: -12)
const PORT_INSET := 6.0                # m in from the platform's inner edge (where it meets the ring) the port's inner wall stands - clear of the ring
const PORT_ROOMS := 40.0               # m out past the platform: the concourse, the rooms, their windows
var _finished := false


## A part of the station: a box, a cylinder or the beacon's ball - where it
## is, its look. Data only; placed the way a Node3D is (position, rotation, basis).
class Part:
	var kind := 0                 # 0 box, 1 cylinder, 2 ball
	var size := Vector3.ZERO      # a box's size; a cylinder's (top radius, height, bottom radius); a ball's radius in x
	var seg := 0
	var look := ""
	var position := Vector3.ZERO
	var basis := Basis.IDENTITY
	var name := ""
	var rotation: Vector3:
		get:
			return basis.get_euler()
		set(v):
			basis = Basis.from_euler(v)

	func rotate_object_local(axis: Vector3, angle: float) -> void:
		basis = basis * Basis(axis, angle)


## The decoration, recorded as it's laid out (EmpireKit.Mesher's calls, by
## name): the worker that bakes the station plays it back into the mesh.
class Dress:
	var ops: Array = []

	func panel(mid: Vector3, right: Vector3, down: Vector3, zone: int, facing: Vector3, g := 0.0) -> void:
		ops.append(["panel", [mid, right, down, zone, facing, g]])

	func disc(mid: Vector3, normal: Vector3, up: Vector3, r: float, zone: int, seg := 32) -> void:
		ops.append(["disc", [mid, normal, up, r, zone, seg]])

	func cyl(a: Vector3, b: Vector3, ra: float, rb: float, zone: int, seg := 12, caps := true) -> void:
		ops.append(["cyl", [a, b, ra, rb, zone, seg, caps]])

	func boxat(size: Vector3, at: Vector3, zone: int, yaw := 0.0) -> void:
		ops.append(["boxat", [size, at, zone, yaw]])

	func slab(pts: PackedVector2Array, xf: Transform3D, t: float, zone: int, edge: int) -> void:
		ops.append(["slab", [pts, xf, t, zone, edge]])


## `staged`: only its parts laid out now (a loading step) - `finish` does the
## rest (its solids, the bake's start, the pads' lights) in the next.
func setup(st: Dictionary, staged := false) -> void:
	record = st
	add_to_group("cam_solid")   # (the camera stops short of its parts)
	set_meta("cam_reach", 2200.0)
	name = str(st.get("name", "Station")).replace(" ", "_")
	set_meta("edit_key", "station/%s/%s" % [str(st.get("empire", "")), str(st.get("id", name))])   # (the Live Editor's edits: this station - its id seeds its layout)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(st.get("id", name)))
	var emp := str(st.get("empire", ""))
	_mats = {"pad": _mat(Color(0.2, 0.21, 0.23), 0.4, 0.7)}
	_empire(rng, emp if EmpireKit.LOOKS.has(emp) else "")
	rotation.y = rng.randf() * TAU
	if not staged:
		finish()


var turrets: Array = []        # its guns (CosmosLaw fires them): Node3D [base, head (turns; its barrels along -z)]
var _glass: Array = []         # [middle, basis, size (along, high)]: the ports' windows


func finish() -> void:
	if _finished:
		return
	_finished = true
	if not _glass.is_empty():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for g in _glass:
			var c: Vector3 = g[0]
			var bb: Basis = g[1]
			var sz: Vector2 = g[2]
			var r: Vector3 = bb.z * sz.x * 0.5
			var u: Vector3 = Vector3.UP * sz.y * 0.5
			for v in [c - r - u, c + r - u, c + r + u, c - r - u, c + r + u, c - r + u]:
				st.set_normal(bb.x)
				st.add_vertex(v)
		var gi := MeshInstance3D.new()
		gi.name = "Windows"
		gi.mesh = st.commit()
		var gm := EmpireKit.glass().duplicate() as StandardMaterial3D
		gm.cull_mode = BaseMaterial3D.CULL_DISABLED   # (seen from inside the rooms too)
		gi.material_override = gm
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.set_meta("keep", true)
		add_child(gi)
	_shutters()
	_turrets()
	bay = pads[0]["at"] if not pads.is_empty() else Vector3.ZERO
	_collect_solids()
	SolidsEdit.installed(self)   # (its solids as edited in the Live Editor, if they were)
	_bake()
	set_process(true)   # (till the bake's in: _process - it may have stopped itself a frame ago, staged)
	_merge()   # (the pads' lights, a mesh a pad)


# --- The empires' stations ------------------------------------------------------------
# Each from its reference sheet (external/images/<empire>_spacestations_1.png): a
# ring, a hub in the middle with the empire's emblem, spokes, its own ornaments -
# in the empire's look (EmpireKit: colours, emblem, frieze). Solid parts are
# boxes and cylinders (_piece: bumped into, baked into one mesh - _bake); the
# rest (columns, friezes, banners, roundels, rails) goes into `_dress`, drawn
# only. The ring holds still: the landing platforms stand out from it.

var _emp := ""
var _dress: Dress


func _empire(rng: RandomNumberGenerator, emp: String) -> void:
	_emp = emp
	var L := EmpireKit.look(emp)
	for k in [["hull", EmpireKit.MAIN], ["paint", EmpireKit.ACCENT], ["paint2", EmpireKit.ACCENT2], ["dark", EmpireKit.IRON],
			["trim", EmpireKit.GOLD], ["steel", EmpireKit.STEEL]]:
		_mats[k[0]] = EmpireKit.zone_mat(k[1], "station", emp)
	var lamp: Color = L["lamp"]
	_mats["glow"] = _mat(lamp, 0.0, 0.5, lamp * 3.0)
	_mats["lights"] = _mat(lamp, 0.0, 0.5, lamp * 2.4)
	_ring = Node3D.new()
	_ring.name = "Ring"
	add_child(_ring)
	_dress = Dress.new()
	var at: Array   # [the radius its platforms stand out from, their decks' height]
	match emp:
		"athens": at = _athens(rng)
		"sparta": at = _sparta(rng)
		"mycenae": at = _mycenae(rng)
		"ionia": at = _ionia(rng)
		"cyclades": at = _cyclades(rng)
		"pirates": at = _pirates(rng)
		"minoa": at = _minoan(rng)
		_: at = _plain(rng)
	_ring_platforms(at[0], at[1])
	reach = float(at[0]) + PAD_LARGE + 80.0


static func _out(a: float) -> Vector3:
	return Vector3(cos(a), 0, sin(a))


## A box on the circle (angle `a`, radius `r`, height `y`; `off` along the
## circle): its x along the circle, its z outward.
func _arc(a: float, r: float, y: float, size: Vector3, look: String, off := 0.0) -> Part:
	var o := _out(a)
	var mi := _piece(_pb(size), look, o * r + Vector3(0, y, 0) - o.cross(Vector3.UP) * off)
	mi.rotation.y = -a + PI * 0.5
	return mi


## A box along a radius (from r0 out to r1): `w` wide, `h` high.
func _radial(a: float, r0: float, r1: float, y: float, w: float, h: float, look: String) -> Part:
	var mi := _piece(_pb(Vector3(r1 - r0, h, w)), look, _out(a) * (r0 + r1) * 0.5 + Vector3(0, y, 0))
	mi.rotation.y = -a
	return mi


## Drums stacked on the axis: [middle's y, top radius, height, bottom radius, look, lit band?].
func _tiers(list: Array, seg := 32) -> void:
	for t in list:
		_piece(_pc(t[1], t[3], t[2], seg), t[4], Vector3(0, t[0], 0))
		if t.size() < 6 or t[5]:
			var r := maxf(t[1], t[3]) * 1.01
			_piece(_pc(r, r, 4.0, seg), "lights", Vector3(0, float(t[0]) + float(t[2]) * 0.15, 0))


## A dome of stepped drums from y0 up (`down`: hanging under it): `r` at its foot, `steps` of it, `frac` of the quarter turn.
func _dome(y0: float, r: float, steps: int, look: String, frac := 0.9, down := false, seg := 32) -> float:
	var y := y0
	for k in steps:
		var a0 := PI * 0.5 * frac * k / steps
		var a1 := PI * 0.5 * frac * (k + 1) / steps
		var h := r * (sin(a1) - sin(a0))
		var top := r * cos(a1)
		var bot := r * cos(a0)
		_piece(_pc(bot if down else top, top if down else bot, h, seg), look, Vector3(0, y + (-h if down else h) * 0.5, 0))
		y += -h if down else h
	return y


## A spike (a cone) from `at` along `dir`.
func _spike(at: Vector3, dir: Vector3, length: float, r: float, look: String) -> void:
	var mi := _piece(_pc(0.4, r, length, 8), look, at + dir * length * 0.5)
	var x := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	mi.basis = Basis(x, dir, x.cross(dir))


## The frieze on a face out from the axis (or `inward`), its middle at angle `a`, radius `r`, height `y`.
func _frieze(a: float, r: float, y: float, half_len: float, half_h: float, reps: int, inward := false) -> void:
	var o := _out(a) * (-1.0 if inward else 1.0)
	_dress.panel(_out(a) * r + Vector3(0, y, 0), o.cross(Vector3.UP) * half_len, Vector3(0, -half_h, 0), EmpireKit.FRIEZE, o, reps / 40.0)


## A banner hung with its top at `top`, facing `o`.
func _banner(top: Vector3, o: Vector3, half_w: float, h: float) -> void:
	_dress.panel(top - Vector3(0, h * 0.5, 0), o.cross(Vector3.UP).normalized() * half_w, Vector3(0, -h * 0.5, 0), EmpireKit.BANNER, o)


## The emblem on a disc, flat, facing up (or down).
func _roundel(at: Vector3, r: float, down := false) -> void:
	_dress.disc(at, Vector3.DOWN if down else Vector3.UP, Vector3.FORWARD, r, EmpireKit.ROUNDEL, 40)


## A row of columns (drawn only): `n` from `from` every `step`, `h` high.
func _columns(from: Vector3, step: Vector3, n: int, r: float, h: float, zone := EmpireKit.MAIN) -> void:
	for j in n:
		var p := from + step * j
		_dress.cyl(p, p + Vector3(0, h, 0), r * 1.12, r * 0.92, zone, 10, false)
		_dress.boxat(Vector3(r * 3.0, r * 0.7, r * 3.0), p + Vector3(0, h - r * 0.35, 0), zone)


## The landing platforms: four out from the ring's outer face at `r_out`, their
## decks at `y` - railed, lamps along their rims, floodlit, a banner under each.
func _ring_platforms(r_out: float, y: float) -> void:
	var pad_id := 1
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var dir := _out(a)
		var big := i % 2 == 0
		var pw := PAD_LARGE + 60.0 if big else PAD_SMALL * 3.0 + 80.0
		var pd := PAD_LARGE + 60.0 if big else PAD_SMALL + 70.0
		var centre := dir * (r_out + pd * 0.5 - 4.0) + Vector3(0, y, 0)
		var side := dir.cross(Vector3.UP)
		var n := 1 if big else 3
		var holes: Array = []
		for j in n:
			holes.append([(j - (n - 1) * 0.5) * (PAD_SMALL + 20.0), PAD_LARGE if big else PAD_SMALL])
		_platform(centre, -a, pd, pw, holes)
		var rec := {"centre": centre, "yaw": -a, "pd": pd, "pw": pw, "big": big, "pads": [], "holes": holes}
		for h in holes:
			_pad(pad_id, centre + side * float(h[0]) + Vector3(0, 12.4, 0), h[1], -a, (pd - float(h[1])) * 0.5)
			pads[pads.size() - 1]["platform"] = platforms.size()
			pads[pads.size() - 1]["along"] = float(h[0])
			rec["pads"].append(pad_id)
			pad_id += 1
		platforms.append(rec)
		var top := centre + Vector3(0, 12.0, 0)
		for e in [[dir * (pd * 0.5 - 2.0), side * (pw * 0.5)], [side * (pw * 0.5 - 2.0), dir * (pd * 0.5)], [-side * (pw * 0.5 - 2.0), dir * (pd * 0.5)]]:
			var o: Vector3 = top + e[0]
			var half: Vector3 = e[1]
			_dress.cyl(o - half + Vector3(0, 4.5, 0), o + half + Vector3(0, 4.5, 0), 0.35, 0.35, EmpireKit.STEEL, 6, false)
			_dress.cyl(o - half + Vector3(0, 0.4, 0), o + half + Vector3(0, 0.4, 0), 0.5, 0.5, EmpireKit.LAMP, 6, false)
			var posts := int(half.length() * 2.0 / 12.0)
			for q in posts + 1:
				var pp := o - half + half * 2.0 * q / maxf(posts, 1)
				_dress.cyl(pp, pp + Vector3(0, 4.5, 0), 0.3, 0.3, EmpireKit.STEEL, 4, false)
		_banner(centre + dir * (pd * 0.5 + PORT_ROOMS + 1.0) - Vector3(0, 14.0, 0), dir, 12.0, 26.0)   # (on the port's outer wall)
		var flood := OmniLight3D.new()
		flood.light_color = (EmpireKit.look(_emp)["lamp"] as Color).lerp(Color(1.0, 0.9, 0.75), 0.6)
		flood.light_energy = 3.0
		flood.omni_range = pw * 1.3
		flood.omni_attenuation = 0.6
		flood.shadow_enabled = false
		flood.position = centre + Vector3(0, 110.0, 0) - dir * pd * 0.3
		add_child(flood)


## The Minoans': a great ring of chamfered segments (cream, worn, red bands,
## the wave frieze along it, windows lit in rows) on spokes and bridges round
## a tower of stacked discs - a spire above, one hanging below - the bull's
## banners hung from the ring and the hub.
func _minoan(rng: RandomNumberGenerator) -> Array:
	var ring_r := rng.randf_range(820.0, 920.0)
	var W := 120.0                 # (the ring's section: wide, tall)
	var H := 110.0
	var C := 22.0                  # (its chamfers)
	var segs := 32
	var seg_len := ring_r * TAU / segs
	for i in segs:
		var a := TAU * (i + 0.5) / segs
		var out := _out(a)
		var at := out * ring_r
		var yaw := -a + PI * 0.5
		var red := i % 4 == 1
		_arc(a, ring_r, 0.0, Vector3(seg_len * 1.01, H - C * 2.0, W), "paint" if red else "hull")
		_arc(a, ring_r, 0.0, Vector3(seg_len * 1.005, H, W - C * 2.0), "hull")
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:   # (the four chamfers, plates at 45 degrees)
				var ch := _piece(_pb(Vector3(seg_len * 1.003, C * 1.414, 6.0)), "paint" if (red or (sy > 0 and i % 2 == 0)) else "hull",
					at + Vector3(0, sy * (H * 0.5 - C * 0.5), 0) + out * sz * (W * 0.5 - C * 0.5))
				ch.rotation = Vector3(0, yaw, 0)
				ch.rotate_object_local(Vector3.RIGHT, -sy * sz * PI * 0.25)
		for side in [-1.0, 1.0]:   # (windows lit in rows, inside and out)
			for row in [-24.0, -8.0]:
				_arc(a, ring_r + side * (W * 0.5 + 0.4), row, Vector3(seg_len * 0.86, 5.0, 1.5), "lights")
		if i % 2 == 0:
			_frieze(a, ring_r + W * 0.5 + 0.8, 18.0, seg_len * 0.48, 10.0, 6)
		if i % 8 == 3:   # (towers on the ring, now and then)
			_arc(a, ring_r, H * 0.5 + 23.0, Vector3(34, 46, 34), "hull")
			_piece(_pc(1.5, 2.5, 90, 6), "dark", at + Vector3(8, H * 0.5 + 90.0, 0))
		if i % 4 == 2:   # (banners under it)
			_banner(at + out * (W * 0.5 + 2.0) - Vector3(0, H * 0.5, 0), out, 16.0, 88.0)
	# The tower: discs stacked on a column, a spire up, one hanging down.
	_tiers([[-520.0, 30.0, 20.0, 160.0, "dark"], [-380.0, 120.0, 60.0, 140.0, "hull"], [-240.0, 200.0, 50.0, 130.0, "paint"],
		[-40.0, 260.0, 120.0, 260.0, "hull"], [90.0, 150.0, 150.0, 150.0, "hull"], [200.0, 230.0, 40.0, 230.0, "paint"],
		[320.0, 110.0, 200.0, 110.0, "hull"], [460.0, 160.0, 36.0, 160.0, "hull"]])
	_piece(_pc(60.0, 90.0, 200.0, 16), "hull", Vector3(0, 580.0, 0))
	_piece(_pc(18.0, 40.0, 260.0, 12), "hull", Vector3(0, 800.0, 0))
	_piece(_pc(3.0, 14.0, 220.0, 8), "dark", Vector3(0, 1040.0, 0))
	_piece(_ps(10.0), "glow", Vector3(0, 1160.0, 0)).name = "Beacon"
	for k in 6:
		var a := TAU * k / 6.0
		_piece(_pc(1.2, 3.0, 120.0 + 40.0 * (k % 3), 6), "dark", Vector3(cos(a) * 75.0, 680.0 + 20.0 * (k % 3), sin(a) * 75.0))
	_piece(_pc(30.0, 120.0, 240.0, 16), "hull", Vector3(0, -720.0, 0))
	_piece(_pc(4.0, 30.0, 240.0, 12), "dark", Vector3(0, -960.0, 0))
	for k in 4:   # (the hub's banners)
		var o := _out(TAU * (k + 0.5) / 4.0)
		_banner(o * 262.0 + Vector3(0, -105.0, 0), o, 22.0, 120.0)
	# Spokes and bridges out to the ring.
	for k in 6:
		var a := TAU * k / 6.0
		var r1 := ring_r - W * 0.5
		var sp := _radial(a, 140.0, r1, -10.0 if k % 2 else 18.0, 36.0, 30.0, "hull")
		_radial(a, 140.0 + (r1 - 140.0) * 0.05, r1 - (r1 - 140.0) * 0.05, sp.position.y + 4.0, 37.0, 4.0, "lights")
		_radial(a + 0.08, 150.0, r1, 40.0, 14.0, 8.0, "dark")
	return [ring_r + W * 0.5, -H * 0.5 + 12.0]


## A temple front on the ring at angle `a` (Athens'): a stylobate, a cella
## behind its columns, the entablature with its frieze, a navy roof, the
## pediment and the emblem in it - facing out and in.
func _temple(a: float, r: float, y0: float, w: float, d: float, h: float) -> void:
	var o := _out(a)
	var tan := o.cross(Vector3.UP)
	var at := o * r
	_arc(a, r, y0 + 4.0, Vector3(w, 8.0, d), "hull")
	_arc(a, r, y0 + 8.0 + h * 0.5, Vector3(w * 0.6, h, d * 0.62), "hull")
	for sd in [-1.0, 1.0]:
		_columns(at + o * sd * (d * 0.5 - 9.0) - tan * (w * 0.5 - 10.0) + Vector3(0, y0 + 8.0, 0), tan * ((w - 20.0) / 5.0), 6, 6.0, h)
		_columns(at + tan * sd * (w * 0.5 - 10.0) - o * (d * 0.5 - 9.0 - (d - 18.0) / 4.0) + Vector3(0, y0 + 8.0, 0), o * ((d - 18.0) / 4.0), 3, 6.0, h)
	var ey := y0 + 8.0 + h
	_arc(a, r, ey + 6.0, Vector3(w, 12.0, d), "hull")
	_arc(a, r, ey + 13.0, Vector3(w + 4.0, 3.0, d + 4.0), "trim")
	for sd in [-1.0, 1.0]:
		_frieze(a, r + sd * (d * 0.5 + 0.6), ey + 6.0, w * 0.48, 5.0, 12, sd < 0.0)
	var hw := w * 0.5 + 2.0
	var slope := 0.3
	var rise := hw * tan(slope)
	for s in [-1.0, 1.0]:   # (the roof's two slopes, the ridge along the way out)
		var rf := _arc(a, r, ey + 14.5 + rise * 0.5, Vector3(hw / cos(slope), 5.0, d + 6.0), "paint", s * hw * 0.5)
		rf.rotate_object_local(Vector3.BACK, -s * slope)
	for sd in [-1.0, 1.0]:   # (the pediments: the gable's triangle, the emblem in it)
		var org: Vector3 = at + o * sd * (d * 0.5 + 1.0) + Vector3(0, ey + 14.5, 0)
		_dress.slab(PackedVector2Array([Vector2(-hw, 0), Vector2(hw, 0), Vector2(0, rise)]), Transform3D(Basis(tan, o * sd, Vector3.UP), org), 3.0,
			EmpireKit.MAIN, EmpireKit.GOLD)
		_dress.disc(org + Vector3(0, rise * 0.36, 0) + o * sd * 2.0, o * sd, Vector3.UP, rise * 0.3, EmpireKit.ROUNDEL, 24)


## Athens': a marble ring under navy roofs with gold cornices and the meander
## along it, four temples on it; in the middle a tholos - a round colonnade
## under a cone of a roof, the owl on its crown - on stoas (colonnaded arms)
## out to the temples.
func _athens(rng: RandomNumberGenerator) -> Array:
	var R := rng.randf_range(830.0, 900.0)
	var W := 96.0
	var H := 72.0
	var segs := 36
	var sl := R * TAU / segs
	for i in segs:
		var a := TAU * (i + 0.5) / segs
		_arc(a, R, 0.0, Vector3(sl * 1.01, H, W), "hull")
		_arc(a, R, H * 0.5 + 5.0, Vector3(sl * 1.012, 10.0, W * 0.8), "paint")
		for side in [-1.0, 1.0]:
			_arc(a, R + side * (W * 0.5 - 2.0), H * 0.5 + 2.0, Vector3(sl * 1.014, 5.0, 6.0), "trim")
			_arc(a, R + side * (W * 0.5 + 0.4), -16.0, Vector3(sl * 0.8, 6.0, 1.5), "lights")
		_frieze(a, R + W * 0.5 + 0.8, 14.0, sl * 0.5, 9.0, 8)
	for k in 4:
		_temple(TAU * k / 4.0, R, H * 0.5 + 10.0, 170.0, 130.0, 80.0)
	# The tholos.
	_tiers([[-470.0, 30.0, 24.0, 120.0, "dark"], [-380.0, 150.0, 70.0, 110.0, "hull"], [-270.0, 220.0, 50.0, 160.0, "paint"],
		[-170.0, 180.0, 90.0, 180.0, "hull"], [-70.0, 240.0, 110.0, 240.0, "hull"], [-9.0, 248.0, 12.0, 248.0, "trim", false]])
	_piece(_pc(150.0, 150.0, 120.0, 32), "hull", Vector3(0, 57.0, 0))
	_piece(_pc(151.5, 151.5, 5.0, 32), "lights", Vector3(0, 60.0, 0))
	for j in 20:
		var o := _out(TAU * j / 20.0)
		_columns(o * 208.0 + Vector3(0, -3.0, 0), Vector3.ZERO, 1, 9.0, 120.0)
	_tiers([[125.0, 238.0, 16.0, 238.0, "hull", false], [136.0, 244.0, 6.0, 244.0, "trim", false], [170.0, 116.0, 62.0, 240.0, "paint", false],
		[204.0, 118.0, 6.0, 118.0, "trim", false]])
	_roundel(Vector3(0, 207.4, 0), 108.0)
	_roundel(Vector3(0, -482.5, 0), 26.0, true)
	_piece(_pc(6.0, 10.0, 240.0, 8), "trim", Vector3(-150.0, 250.0, 0))   # (a mast beside the crown, its lamp)
	_piece(_ps(9.0), "glow", Vector3(-150.0, 376.0, 0)).name = "Beacon"
	_piece(_pc(4.0, 30.0, 200.0, 12), "dark", Vector3(0, -582.0, 0))
	# The stoas out to the temples; struts to the platforms' sides.
	for k in 4:
		var a := TAU * k / 4.0
		var o := _out(a)
		var tan := o.cross(Vector3.UP)
		var r1 := R - W * 0.5
		_radial(a, 235.0, r1, -30.0, 52.0, 34.0, "hull")
		_radial(a, 235.0, r1, -10.0, 60.0, 6.0, "paint")
		_radial(a, 250.0, r1 - 10.0, -32.0, 53.0, 4.0, "lights")
		var n := int((r1 - 265.0) / 30.0)
		for sd in [-1.0, 1.0]:
			_columns(o * 262.0 + tan * sd * 29.0 + Vector3(0, -47.0, 0), o * 30.0, n, 3.2, 34.0)
		_radial(a + PI * 0.25, 230.0, r1, -40.0, 16.0, 14.0, "dark")
	return [R + W * 0.5, -H * 0.5 + 12.0]


## Sparta's: a fortress - an eight-sided wall of iron under cream and crimson
## armour, a bastion at each corner (the lambda on its roof, a gun turret), gold
## spear tips out from four of them; in the middle an eight-sided keep, the
## lambda great on its roof.
func _sparta(rng: RandomNumberGenerator) -> Array:
	var R := rng.randf_range(820.0, 880.0)      # (the wall's sides this far out)
	var W := 130.0
	var H := 100.0
	var side := 2.0 * R * tan(PI / 8.0)
	var Rv := R / cos(PI / 8.0)
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		_arc(a, R, 0.0, Vector3(side + W * 0.3, H, W), "dark")
		for j in 5:   # (its armour: plates out and on top, cream and crimson in turn)
			var off := (j - 2) * side / 5.0
			var look := "paint" if (i + j) % 2 == 0 else "hull"
			_arc(a, R + W * 0.5 + 2.0, 4.0, Vector3(side / 5.0 - 8.0, H - 26.0, 6.0), look, off)
			_arc(a, R, H * 0.5 + 2.5, Vector3(side / 5.0 - 8.0, 5.0, W - 24.0), "hull" if (i + j) % 2 == 0 else "paint", off)
			_arc(a, R + W * 0.5 + 5.4, -6.0, Vector3(side / 5.0 - 40.0, 4.0, 1.5), "lights", off)
			_arc(a, R - W * 0.5 - 0.4, -6.0, Vector3(side / 5.0 - 40.0, 4.0, 1.5), "lights", off)
		_frieze(a, R + W * 0.5 + 5.6, 36.0, side * 0.46, 6.0, 30)
		# (a bastion at the corner, the lambda on its roof, a turret; a spear tip from every other)
		var av := TAU * i / 8.0
		var o := _out(av)
		_piece(_pc(108.0, 118.0, H + 70.0, 8), "paint", o * Rv + Vector3(0, 10.0, 0))
		_piece(_pc(122.0, 122.0, 16.0, 8), "hull", o * Rv + Vector3(0, H * 0.5 + 40.0, 0))
		_roundel(o * Rv + Vector3(0, H * 0.5 + 48.6, 0), 92.0)
		_dress.boxat(Vector3(30.0, 14.0, 30.0), o * (Rv + 96.0) + Vector3(0, H * 0.5 + 30.0, 0), EmpireKit.IRON, -av)
		for q in [-8.0, 0.0, 8.0]:
			var mz: Vector3 = o * (Rv + 108.0) + o.cross(Vector3.UP) * q + Vector3(0, H * 0.5 + 30.0, 0)
			_dress.cyl(mz, mz + o * 70.0, 2.4, 2.0, EmpireKit.IRON, 6)
		if i % 2 == 0:
			_spike(o * (Rv + 116.0), o, 260.0, 26.0, "trim")
	# The keep.
	_tiers([[-420.0, 40.0, 30.0, 150.0, "dark"], [-320.0, 180.0, 80.0, 150.0, "paint"], [-200.0, 230.0, 70.0, 200.0, "dark"],
		[0.0, 250.0, 150.0, 250.0, "paint"], [-40.0, 257.0, 26.0, 257.0, "hull", false], [81.0, 236.0, 12.0, 236.0, "dark", false]], 8)
	_roundel(Vector3(0, 87.6, 0), 196.0)
	_roundel(Vector3(0, -435.5, 0), 34.0, true)
	for k in 4:
		var o := _out(TAU * (k + 0.5) / 4.0)
		_piece(_pc(26.0, 30.0, 130.0, 8), "dark", o * 214.0 + Vector3(0, 110.0, 0))
		_piece(_ps(7.0), "glow", o * 214.0 + Vector3(0, 180.0, 0))
	_piece(_pc(4.0, 34.0, 220.0, 8), "dark", Vector3(0, -545.0, 0))
	for k in 4:
		var a := TAU * k / 4.0
		_radial(a, 240.0, Rv - 100.0, 0.0, 72.0, 52.0, "dark")
		_radial(a, 260.0, Rv - 110.0, 28.5, 60.0, 5.0, "paint")
		_radial(a, 260.0, Rv - 110.0, 4.0, 73.0, 4.0, "lights")
		_radial(a + PI * 0.25, 240.0, R - W * 0.5, -20.0, 24.0, 20.0, "dark")
	return [Rv + 124.0, -H * 0.5 + 12.0]   # (the platforms out from the bastions' faces - they stand where the platforms do)


## Mycenae's: a citadel - a wall of great uneven blocks of stone, red bands
## and gold studs on it, rosettes along it; in the middle a tholos, the
## corbelled dome of the old tombs, gold on its crown; gold shields on the
## stone arms out to the wall.
func _mycenae(rng: RandomNumberGenerator) -> Array:
	var R := rng.randf_range(830.0, 890.0)
	var W := 120.0
	var segs := 24
	var sl := R * TAU / segs
	for i in segs:
		var a := TAU * (i + 0.5) / segs
		var h := rng.randf_range(84.0, 132.0)
		var w := W + rng.randf_range(-8.0, 26.0)
		_arc(a, R, -5.0, Vector3(sl * 1.02, 76.0, W * 0.8), "dark")
		_arc(a, R + (w - W) * 0.25, h * 0.5 - 50.0, Vector3(sl * 0.955, h, w), "hull")
		var ro := R + (w - W) * 0.25 + w * 0.5
		if i % 3 == 1:
			_arc(a, ro + 0.6, 10.0, Vector3(sl * 0.9, 12.0, 2.0), "paint")
			for q in [-1.0, 0.0, 1.0]:
				_arc(a, ro + 2.0, 10.0, Vector3(7.0, 7.0, 3.0), "trim", q * sl * 0.3)
		elif i % 3 == 0:
			_frieze(a, ro + 0.8, 8.0, sl * 0.44, 9.0, 8)
		for q in [-1.0, 1.0]:
			_arc(a, ro + 0.4, -22.0, Vector3(9.0, 12.0, 1.5), "lights", q * sl * 0.22)
			_arc(a, R - W * 0.4 - 0.4, -18.0, Vector3(sl * 0.3, 5.0, 1.5), "lights", q * sl * 0.22)
	# The tholos.
	_tiers([[-460.0, 40.0, 30.0, 140.0, "dark"], [-360.0, 170.0, 80.0, 140.0, "hull"], [-240.0, 250.0, 60.0, 180.0, "dark"],
		[-130.0, 200.0, 100.0, 200.0, "hull"], [-40.0, 300.0, 80.0, 300.0, "hull"]])
	var top := _dome(0.0, 292.0, 10, "hull", 0.93)
	_piece(_pc(262.0, 262.0, 9.0, 32), "paint", Vector3(0, 62.0, 0))
	_piece(_pc(180.0, 180.0, 7.0, 32), "trim", Vector3(0, 196.0, 0))
	_piece(_pc(8.0, 30.0, 70.0, 12), "trim", Vector3(0, top + 35.0, 0))
	_piece(_ps(9.0), "glow", Vector3(0, top + 80.0, 0)).name = "Beacon"
	_roundel(Vector3(0, -475.5, 0), 34.0, true)
	_piece(_pc(4.0, 34.0, 200.0, 12), "dark", Vector3(0, -575.0, 0))
	for k in 4:
		var a := TAU * k / 4.0
		var o := _out(a)
		var r1 := R - W * 0.5
		_radial(a, 290.0, r1, -12.0, 92.0, 62.0, "hull")
		_radial(a, 300.0, r1 - 10.0, -14.0, 93.0, 4.0, "lights")
		for q in 3:   # (gold bands across it, a gold shield on it: the rosette)
			var rr := lerpf(330.0, r1 - 40.0, q / 2.0)
			_radial(a, rr - 5.0, rr + 5.0, -12.0, 96.0, 66.0, "trim")
		var mid := o * ((290.0 + r1) * 0.5)
		_piece(_pc(72.0, 72.0, 8.0, 24), "trim", mid + Vector3(0, 23.0, 0))
		_roundel(mid + Vector3(0, 27.6, 0), 66.0)
		_radial(a + PI * 0.25, 290.0, r1, -30.0, 30.0, 26.0, "dark")
	return [R + W * 0.5, -38.0]


## Ionia's: an armillary - a slim marble ring inlaid with lapis, a second
## ring within, a lapis dome in the middle with gold rings turned round it,
## arms out to the great ring ending in Ionic volutes, lapis panels between.
func _ionia(rng: RandomNumberGenerator) -> Array:
	var R := rng.randf_range(840.0, 900.0)
	var W := 74.0
	var H := 52.0
	var segs := 40
	var sl := R * TAU / segs
	for i in segs:
		var a := TAU * (i + 0.5) / segs
		_arc(a, R, 0.0, Vector3(sl * 1.01, H, W), "hull")
		_arc(a, R, H * 0.5 + 2.0, Vector3(sl * 1.012, 4.0, W * 0.56), "paint")
		for side in [-1.0, 1.0]:
			_arc(a, R + side * (W * 0.5 - 2.0), H * 0.5 + 1.5, Vector3(sl * 1.014, 4.0, 5.0), "trim")
			_arc(a, R + side * (W * 0.5 + 0.4), -8.0, Vector3(sl * 0.84, 4.0, 1.5), "lights")
		if i % 2 == 0:
			_frieze(a, R + W * 0.5 + 0.8, 10.0, sl * 0.5, 7.0, 8)
	var r2 := R * 0.6
	var sl2 := r2 * TAU / 32.0
	for i in 32:
		var a := TAU * (i + 0.5) / 32.0
		_arc(a, r2, 0.0, Vector3(sl2 * 1.01, 24.0, 30.0), "hull")
		_arc(a, r2, 13.5, Vector3(sl2 * 1.012, 3.0, 18.0), "paint")
		_arc(a, r2 + 15.4, 0.0, Vector3(sl2 * 0.8, 3.0, 1.2), "lights")
	# The dome.
	_tiers([[-330.0, 30.0, 30.0, 110.0, "dark"], [-250.0, 130.0, 70.0, 110.0, "hull"], [0.0, 172.0, 92.0, 172.0, "hull"],
		[49.0, 180.0, 8.0, 180.0, "trim", false]])
	_dome(-46.0, 168.0, 7, "hull", 0.85, true)
	var top := _dome(53.0, 164.0, 9, "paint", 0.94)
	_piece(_pc(4.0, 22.0, 110.0, 12), "trim", Vector3(0, top + 55.0, 0))
	_piece(_ps(9.0), "glow", Vector3(0, top + 118.0, 0)).name = "Beacon"
	_roundel(Vector3(0, -345.5, 0), 26.0, true)
	_piece(_pc(3.0, 26.0, 180.0, 12), "trim", Vector3(0, -435.0, 0))
	for k in 3:   # (the armillary's rings, gold, each turned its own way)
		var bs := Basis(Vector3(1, 0, 0.3 * k).normalized(), 0.5 + 0.55 * k) * Basis(Vector3.UP, k * 1.1)
		for j in 56:
			var p0 := bs * (_out(TAU * j / 56.0) * (300.0 + 26.0 * k))
			var p1 := bs * (_out(TAU * (j + 1) / 56.0) * (300.0 + 26.0 * k))
			_dress.cyl(p0, p1, 4.5, 4.5, EmpireKit.GOLD, 6, false)
	# The arms, their volutes over the ring; lapis panels between them.
	for k in 4:
		var a := TAU * k / 4.0
		var o := _out(a)
		var tan := o.cross(Vector3.UP)
		_radial(a, 172.0, R + W * 0.5 + 30.0, 0.0, 54.0, 38.0, "hull")
		_radial(a, 180.0, R + W * 0.5 + 20.0, 20.5, 34.0, 3.0, "paint")
		_radial(a, 190.0, R - W * 0.5, 4.0, 55.0, 3.0, "lights")
		var cap := R + W * 0.5 + 66.0
		_arc(a, cap, 26.0, Vector3(300.0, 22.0, 76.0), "hull")
		_arc(a, cap, 38.5, Vector3(304.0, 3.0, 80.0), "trim")
		for sd in [-1.0, 1.0]:
			var vc: Vector3 = o * cap + tan * sd * 138.0 + Vector3(0, -14.0, 0)
			var v := _piece(_pc(50.0, 50.0, 78.0, 24), "hull", vc)
			v.basis = Basis(tan, o, tan.cross(o))
			for fs in [-1.0, 1.0]:
				_dress.disc(vc + o * fs * 39.6, o * fs, Vector3.UP, 46.0, EmpireKit.GOLD, 24)
				_dress.disc(vc + o * fs * 40.2, o * fs, Vector3.UP, 34.0, EmpireKit.MAIN, 24)
				_dress.disc(vc + o * fs * 40.8, o * fs, Vector3.UP, 20.0, EmpireKit.GOLD, 20)
				_dress.disc(vc + o * fs * 41.4, o * fs, Vector3.UP, 9.0, EmpireKit.ACCENT, 16)
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		_radial(a, 172.0, R - W * 0.5, 0.0, 12.0, 12.0, "dark")
		if k % 2 == 1:
			_radial(a, r2 + 40.0, R - W * 0.5 - 30.0, 10.0, 120.0, 5.0, "paint")
			_radial(a, r2 + 36.0, R - W * 0.5 - 26.0, 9.0, 128.0, 3.0, "trim")
	return [R + W * 0.5, -H * 0.5 + 12.0]


## The Cyclades': a spiral - two arms of white marble winding out from a
## smooth dome to a slim ring, a lamp's line along them; on the dome an idol,
## tall and plain, its arms folded; spirals in terracotta on drums on the ring.
func _cyclades(rng: RandomNumberGenerator) -> Array:
	var R := rng.randf_range(830.0, 890.0)
	var W := 80.0
	var H := 52.0
	var segs := 36
	var sl := R * TAU / segs
	for i in segs:
		var a := TAU * (i + 0.5) / segs
		_arc(a, R, 0.0, Vector3(sl * 1.01, H, W), "hull")
		_arc(a, R + W * 0.5 + 0.5, 12.0, Vector3(sl * 1.0, 4.0, 1.5), "paint2")
		for side in [-1.0, 1.0]:
			_arc(a, R + side * (W * 0.5 + 0.4), -8.0, Vector3(sl * 0.6, 4.0, 1.5), "lights")
		if i % 6 == 0:
			_arc(a, R, H * 0.5 + 2.0, Vector3(sl * 0.9, 4.0, W * 0.7), "paint")
		if i % 3 == 1:
			_frieze(a, R + W * 0.5 + 0.8, -2.0, sl * 0.48, 8.0, 6)
	for k in 4:
		var o := _out(TAU * k / 4.0)
		_piece(_pc(74.0, 74.0, 16.0, 28), "hull", o * R + Vector3(0, H * 0.5 + 8.0, 0))
		_roundel(o * R + Vector3(0, H * 0.5 + 16.6, 0), 68.0)
	for arm in 2:   # (the spiral's two arms)
		var n := 40
		for j in n:
			var t := (j + 0.5) / n
			var ang := arm * PI + t * TAU * 1.15
			var r := lerpf(215.0, R - W * 0.5 - 6.0, t)
			var ds := Vector2(r * TAU * 1.15 / n, (R - W * 0.5 - 221.0) / n)
			var bx := _arc(ang, r, 0.0, Vector3(ds.length() * 1.2, lerpf(60.0, 36.0, t), lerpf(84.0, 46.0, t)), "hull")
			bx.rotation.y += atan2(ds.y, ds.x)
			var lp := _arc(ang, r, lerpf(60.0, 36.0, t) * 0.5 + 1.2, Vector3(ds.length() * 1.2, 2.4, 8.0), "lights")
			lp.rotation.y += atan2(ds.y, ds.x)
	# The dome, the idol on it; a bowl under it.
	_tiers([[-14.0, 222.0, 60.0, 222.0, "hull"]])
	var top := _dome(16.0, 214.0, 10, "hull", 0.8)
	_dome(-44.0, 214.0, 8, "hull", 0.9, true)
	_piece(_pc(20.0, 30.0, 150.0, 16), "hull", Vector3(0, top + 75.0, 0))                       # (its legs and body)
	_piece(_pb(Vector3(86.0, 60.0, 30.0)), "hull", Vector3(0, top + 170.0, 0))                   # (shoulders, the arms folded)
	_piece(_pb(Vector3(88.0, 8.0, 32.0)), "paint2", Vector3(0, top + 158.0, 0))
	_piece(_pc(12.0, 14.0, 26.0, 12), "hull", Vector3(0, top + 212.0, 0))
	var head := _piece(_pc(30.0, 26.0, 62.0, 16), "hull", Vector3(0, top + 252.0, 6.0))            # (the head: a long oval, tipped back)
	head.rotation.x = -0.22
	_piece(_ps(8.0), "glow", Vector3(0, top + 296.0, 12.0)).name = "Beacon"
	for k in 4:
		_radial(TAU * (k + 0.5) / 4.0, 214.0, R - W * 0.5, -14.0, 18.0, 14.0, "dark")
	return [R + W * 0.5, -H * 0.5 + 12.0]


## The Sea Peoples': a den - a broken ring of dark iron, bone spikes out of it
## and up, red plates, the skull's banners hung under it, teeth along it; in
## the middle a crooked stack, the skull on its roof, masts and red flags.
func _pirates(rng: RandomNumberGenerator) -> Array:
	var R := rng.randf_range(820.0, 880.0)
	var W := 110.0
	var segs := 28
	var sl := R * TAU / segs
	for i in segs:
		var a := TAU * (i + 0.5) / segs
		var near_pad := absf(fposmod(a - PI * 0.25, PI * 0.5) - 0.0) < 0.3 or absf(fposmod(a - PI * 0.25, PI * 0.5) - PI * 0.5) < 0.3
		if not near_pad and rng.randf() < 0.14:
			continue   # (a gap: the ring's broken)
		var h := rng.randf_range(66.0, 112.0)
		var off := 0.0 if near_pad else rng.randf_range(-14.0, 14.0)
		var o := _out(a)
		_arc(a, R + off, 0.0, Vector3(sl * rng.randf_range(0.96, 1.04), h, W + (0.0 if near_pad else rng.randf_range(-12.0, 16.0))), "hull")
		_arc(a, R + off, -4.0, Vector3(sl * 1.02, 44.0, W * 0.7), "dark")
		var ro := R + off + W * 0.5
		if i % 3 == 0:
			_arc(a, ro + 2.0, 6.0, Vector3(sl * 0.7, h * 0.6, 5.0), "paint")
		if i % 2 == 0 and not near_pad:
			_spike(o * (ro + 4.0), (o + Vector3(0, rng.randf_range(-0.2, 0.3), 0)).normalized(), rng.randf_range(90.0, 190.0), 13.0, "paint2")
		if i % 3 == 1:
			_spike(o * (R + off) + Vector3(0, h * 0.5, 0), (Vector3.UP + o * rng.randf_range(-0.3, 0.3)).normalized(), rng.randf_range(50.0, 110.0), 9.0, "paint2")
		if i % 2 == 1:
			_frieze(a, ro + 0.9, -h * 0.5 + 14.0, sl * 0.46, 9.0, 12)
		if i % 4 == 2 and not near_pad:
			_banner(o * (ro + 3.0) - Vector3(0, h * 0.5, 0), o, 15.0, 80.0)
		_arc(a, ro + 0.4, 18.0, Vector3(sl * 0.3, 4.0, 1.5), "lights", sl * 0.2)
		_arc(a, R + off - W * 0.5 - 0.4, 0.0, Vector3(sl * 0.4, 4.0, 1.5), "lights")
	# The stack in the middle.
	_tiers([[-420.0, 30.0, 40.0, 130.0, "dark"], [-320.0, 190.0, 90.0, 120.0, "hull"], [-210.0, 150.0, 70.0, 230.0, "dark"],
		[-70.0, 250.0, 160.0, 210.0, "hull"], [30.0, 215.0, 40.0, 262.0, "paint"], [70.0, 200.0, 36.0, 200.0, "dark", false]], 10)
	_roundel(Vector3(0, 88.6, 0), 180.0)
	for k in 7:   # (spikes hanging under it)
		var o := _out(TAU * k / 7.0 + 0.4)
		_spike(o * 120.0 + Vector3(0, -440.0, 0), (Vector3.DOWN + o * 0.35).normalized(), rng.randf_range(120.0, 240.0), 16.0, "paint2")
	for k in 3:   # (masts, crooked, a red flag on each)
		var o := _out(TAU * k / 3.0 + 0.9)
		var foot := o * 215.0 + Vector3(0, 80.0, 0)
		var up := (Vector3.UP + o * 0.18).normalized()
		_spike(foot, up, 330.0, 7.0, "dark")
		_banner(foot + up * 300.0, o.cross(Vector3.UP), 26.0, 110.0)
		_piece(_ps(6.0), "glow", foot + up * 334.0)
	for k in 4:
		_radial(TAU * (k + 0.5) / 4.0 + rng.randf_range(-0.03, 0.03), 205.0, R - W * 0.5, rng.randf_range(-24.0, 6.0), 30.0, 26.0, "dark")
	for k in 3:
		_radial(TAU * k / 3.0 + rng.randf_range(0.0, 0.5), 205.0, R - W * 0.5 - 10.0, rng.randf_range(-10.0, 20.0), 14.0, 12.0, "dark")
	return [R + W * 0.5, -30.0]


## The independents': a plain tower of stacked drums with a mast and a beacon,
## a ring of segments on spokes, solar wings off the tower.
func _plain(rng: RandomNumberGenerator) -> Array:
	var core_r := rng.randf_range(120.0, 170.0)
	var y := -560.0
	var k := 0
	while y < 600.0:
		var h := rng.randf_range(90.0, 220.0)
		var r := core_r * (1.0 if k % 2 == 0 else rng.randf_range(0.7, 1.25))
		_piece(_pc(r, r, h, 24), "hull" if k % 3 else "paint", Vector3(0, y + h * 0.5, 0))
		_piece(_pc(r * 1.04, r * 1.04, 6.0, 24), "lights", Vector3(0, y + h * 0.5, 0))   # (a band of windows)
		y += h
		k += 1
	_piece(_pc(core_r * 0.3, core_r * 0.6, 140.0, 12), "dark", Vector3(0, y + 70.0, 0))
	_piece(_pc(4.0, 4.0, 260.0, 6), "dark", Vector3(0, y + 270.0, 0))
	_piece(_ps(12.0), "glow", Vector3(0, y + 405.0, 0)).name = "Beacon"
	_roundel(Vector3(0, y + 0.6, 0), core_r * 0.5)
	var ring_r := rng.randf_range(800.0, 900.0)
	var segs := 36
	var sl := ring_r * TAU / segs
	for i in segs:
		var a := TAU * (i + 0.5) / segs
		var painted := i % 4 == 0   # (a touch bigger than its plain neighbours: their faces never meet in one plane)
		_arc(a, ring_r, 0.0, Vector3(sl * 1.02, 70.6 if painted else 70.0, 90.6 if painted else 90.0), "paint" if painted else "hull")
		_arc(a, ring_r + 46.0, 0.4, Vector3(sl * 0.8, 8.0, 2.0), "lights")
		if i % 6 == 3:
			_frieze(a, ring_r + 46.2, 22.0, sl * 0.48, 7.0, 6)
	for i in 4:
		_radial(TAU * i / 4.0, core_r * 0.7, ring_r - 45.0, 0.0, 30.0, 26.0, "dark")
	for sd in [-1.0, 1.0]:   # (solar wings)
		var wing := _piece(_pb(Vector3(30, 30, 520)), "dark", Vector3(0, 420.0, sd * (core_r + 240.0)))
		for q in 3:
			var p := _piece(_pb(Vector3(220, 4, 150)), "paint2", wing.position + Vector3(0, 0, sd * (-150.0 + q * 160.0)))
			p.rotation = Vector3(0, 0, 0.4)
	return [ring_r + 45.0, -35.0 + 12.0]


## An empire's station's parts (boxes, cylinders) as one mesh in its
## look, made on a worker (EmpireKit's faces, each part's zone by its
## material) - one draw for it all; the solids are already taken. Until it's
## done (a frame or two) there's nothing to see.
var _bake_task := -1
var _bake_out: Array = []


func _bake() -> void:
	var zone := {"hull": EmpireKit.MAIN, "paint": EmpireKit.ACCENT, "dark": EmpireKit.IRON, "lights": EmpireKit.LAMP, "glow": EmpireKit.LAMP,
		"trim": EmpireKit.GOLD, "paint2": EmpireKit.ACCENT2, "steel": EmpireKit.STEEL}
	var data: Array = []
	for p: Part in _parts:   # (plain numbers for the worker)
		data.append([p.kind, p.size, Transform3D(p.basis, p.position), int(zone.get(p.look, EmpireKit.MAIN)), p.seg])
	var ops: Array = _dress.ops if _dress else []
	_dress = null
	_bake_task = Jobs.add(func():
		var m := EmpireKit.Mesher.new()
		for d in data:
			var xf: Transform3D = d[2]
			var sz: Vector3 = d[1]
			match int(d[0]):
				0: m.box(sz, xf, d[3])
				1: m.cyl(xf * Vector3(0, -sz.y * 0.5, 0), xf * Vector3(0, sz.y * 0.5, 0), sz.z, sz.x, d[3], d[4])
				_: m.box(Vector3.ONE * sz.x * 1.6, xf, d[3])
		for op in ops:
			m.callv(op[0], op[1])
		_bake_out = m.arrays(), false, "station")


func _bake_poll() -> void:
	if _bake_task < 0 or not Jobs.done(_bake_task):
		return
	Jobs.wait(_bake_task)
	_bake_task = -1
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _bake_out)
	LodKit.later(mesh, [_bake_out])   # (its levels of detail: a far station a fraction of its triangles - LodKit)
	_bake_out = []
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	mi.material_override = EmpireKit.mat("station", _emp)
	add_child(mi)


func _exit_tree() -> void:
	if _bake_task >= 0:
		Jobs.wait(_bake_task)
		_bake_task = -1


## The parts merged into one mesh per material (and per parent: the ring
## turns) - a station of ~250 parts drawn in a dozen draw calls. Kept apart:
## the pads' decks (their lifts move) and each pad's lights (lit for you).
func _merge() -> void:
	var groups := {}
	for parent: Node3D in [self, _ring]:
		for ch in parent.get_children():
			var mi := ch as MeshInstance3D
			if mi == null or mi.has_meta("keep"):
				continue
			var key := "%s|%s|%s" % [parent.get_instance_id(), mi.material_override.get_instance_id(), str(mi.get_meta("group", ""))]
			if not groups.has(key):
				groups[key] = [parent, mi.material_override, SurfaceTool.new(), mi.get_meta("group", "")]
				(groups[key][2] as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
			(groups[key][2] as SurfaceTool).append_from(mi.mesh, 0, mi.transform)
			parent.remove_child(mi)
			mi.free()
	for key in groups:
		var g: Array = groups[key]
		var mi := MeshInstance3D.new()
		mi.mesh = (g[2] as SurfaceTool).commit()
		mi.material_override = g[1]
		(g[0] as Node3D).add_child(mi)
		if str(g[3]) != "":
			for p in pads:
				if "pad%d" % int(p["id"]) == str(g[3]):
					p["glows"] = [mi]


## The camera's line from `o` along `dir`: where it first meets a part (or INF).
func cam_hit(o: Vector3, dir: Vector3, limit: float) -> float:
	var lo := to_local(o)
	var ld := global_basis.inverse() * dir
	if lo.length() > _bound + limit:
		return INF
	var ring_inv := _ring.transform.affine_inverse()
	var best := INF
	for s in _solids:
		var q: Vector3 = ring_inv * lo if s[0] else lo
		var qd: Vector3 = ring_inv.basis * ld if s[0] else ld
		var c: Vector3 = s[1]
		var r: float = s[2]
		# (a quick sphere test first)
		var tc := (c - q).dot(qd)
		if (q + qd * clampf(tc, 0.0, limit)).distance_squared_to(c) > r * r:
			continue
		var inv: Transform3D = s[3]
		var a := inv * q
		var d: Vector3 = inv.basis * qd
		var h: Vector3 = s[4]
		var t0 := 0.0
		var t1 := minf(limit, best)
		var hit := true
		for k in 3:
			if absf(d[k]) < 1e-8:
				if absf(a[k]) > h[k]:
					hit = false
					break
				continue
			var ta := (-h[k] - a[k]) / d[k]
			var tb := (h[k] - a[k]) / d[k]
			if ta > tb:
				var x := ta
				ta = tb
				tb = x
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				hit = false
				break
		if hit and t0 > 0.0:
			best = t0
	return best


func _collect_solids() -> void:
	for p: Part in _parts:
		if p.look == "glow" or p.look == "lights" or p.kind == 2:
			continue
		var r := maxf(p.size.x, p.size.z)
		var half := p.size * 0.5 if p.kind == 0 else Vector3(r, p.size.y * 0.5, r)
		var xf := Transform3D(p.basis, p.position)
		_solids.append([false, xf.origin, half.length(), xf.affine_inverse(), half, p.kind == 1, xf.basis])
		_bound = maxf(_bound, xf.origin.length() + half.length())
	for pd in pads:   # (the pads' decks)
		var deck := pd["deck"] as MeshInstance3D
		var half := (deck.mesh as BoxMesh).size * 0.5
		var xf := deck.transform
		_solids.append([false, xf.origin, half.length(), xf.affine_inverse(), half, false, xf.basis])
		_bound = maxf(_bound, xf.origin.length() + half.length())


## How far to move a ball (at `p`, radius `r`, in the world) to get it out of
## the station's parts: the sum of the pushes (zero when clear).
func push_out(p: Vector3, r: float) -> Vector3:
	var lp := to_local(p)
	if lp.length() > _bound + r:
		return Vector3.ZERO
	var rp := _ring.transform.affine_inverse() * lp
	var total := Vector3.ZERO
	for s in _solids:
		var q: Vector3 = rp if s[0] else lp
		var lim: float = float(s[2]) + r
		if q.distance_squared_to(s[1]) > lim * lim:
			continue
		var l: Vector3 = s[3] * q
		var h: Vector3 = s[4]
		var push := Vector3.ZERO
		if s[5]:
			var rad := Vector2(l.x, l.z)
			var rl := rad.length()
			if absf(l.y) > h.y + r or rl > h.x + r:
				continue
			var side := h.x + r - rl
			var cap := h.y + r - absf(l.y)
			if side < cap:
				push = Vector3(rad.x, 0, rad.y) / maxf(rl, 0.001) * side
			else:
				push = Vector3(0, signf(l.y) if l.y != 0.0 else 1.0, 0) * cap
		else:
			var c := l.clamp(-h, h)
			var d := l - c
			var dl := d.length()
			if dl >= r:
				continue
			if dl > 0.0001:
				push = d / dl * (r - dl)
			else:
				var best := INF
				for a in 3:
					var depth := h[a] - absf(l[a]) + r
					if depth < best:
						best = depth
						push = Vector3.ZERO
						push[a] = depth * (signf(l[a]) if l[a] != 0.0 else 1.0)
		var b: Basis = s[6]
		if s[0]:
			b = _ring.basis * b
		total += global_basis * (b * push)
	return total


## A landing platform (`pd` deep, `pw` wide, turned `yaw`) round the pads'
## shafts (`holes`: [offset across it, pad size]): its deck a frame of parts
## with a square hole for each pad, under each a shaft (lit walls, a floor) the
## pad's lift goes down - the way into the hangar.
func _platform(centre: Vector3, yaw: float, pd: float, pw: float, holes: Array) -> void:
	var b := Basis(Vector3.UP, yaw)
	var put := func(size: Vector3, local: Vector3, look: String) -> void:
		_piece(_pb(size), look, centre + b * local).rotation.y = yaw
	var hs := holes.duplicate()
	hs.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	# The deck, and under it the port's roof - both round the pads' holes.
	for layer in [[0.0, 24.0, "hull", pd, 0.0], [(PORT_CEIL - 12.0) * 0.5, -12.0 - PORT_CEIL, "dark", pd + PORT_ROOMS, PORT_ROOMS * 0.5]]:
		var y: float = layer[0]
		var th: float = layer[1]
		var depth: float = layer[3]
		var xo: float = layer[4]
		var z := -pw * 0.5
		for h in hs:
			var s := float(h[1]) + 1.0
			var z0 := float(h[0]) - s * 0.5
			var z1 := float(h[0]) + s * 0.5
			if z0 > z + 0.01:
				put.call(Vector3(depth, th, z0 - z), Vector3(xo, y, (z + z0) * 0.5), layer[2])
			put.call(Vector3((pd - s) * 0.5, th, s), Vector3(-(s * 0.5 + (pd - s) * 0.25), y, float(h[0])), layer[2])
			var outer := (pd - s) * 0.5 + (depth - pd)
			put.call(Vector3(outer, th, s), Vector3(s * 0.5 + outer * 0.5, y, float(h[0])), layer[2])
			z = z1
		if pw * 0.5 > z + 0.01:
			put.call(Vector3(depth, th, pw * 0.5 - z), Vector3(xo, y, (z + pw * 0.5) * 0.5), layer[2])
	# The port: a module hung under the platform - its floor (the lifts come down
	# onto it), walls, the rooms' strip past the platform's edge with a band of
	# windows along its outer wall. Inside: CosmosHangar.
	var x0 := -pd * 0.5 + PORT_INSET
	var x1 := pd * 0.5 + PORT_ROOMS
	var yf := PORT_FLOOR - 0.1         # (the lifts' decks a little proud of the floor)
	var h := PORT_CEIL - yf
	var mid := (x0 + x1) * 0.5
	put.call(Vector3(x1 - x0 + 4.0, 3.0, pw + 4.0), Vector3(mid, yf - 1.5, 0), "dark")
	put.call(Vector3(2.0, h, pw + 4.0), Vector3(x0 - 1.0, yf + h * 0.5, 0), "hull")
	for sz in [-1.0, 1.0]:
		put.call(Vector3(x1 - x0 + 4.0, h, 2.0), Vector3(mid, yf + h * 0.5, sz * (pw * 0.5 + 1.0)), "hull")
	var w0 := 1.3                     # (the windows: from 1.3 m over the floor to 4.7 m)
	var w1 := 4.7
	put.call(Vector3(2.0, w0, pw + 4.0), Vector3(x1 + 1.0, yf + w0 * 0.5, 0), "hull")
	put.call(Vector3(2.0, h - w1, pw + 4.0), Vector3(x1 + 1.0, yf + w1 + (h - w1) * 0.5, 0), "hull")
	put.call(Vector3(2.4, 0.5, pw + 4.4), Vector3(x1 + 1.0, yf + w1 + 0.25, 0), "trim")
	var n := int(pw / 14.0)
	for k in n + 1:   # (mullions)
		put.call(Vector3(2.2, w1 - w0, 0.6), Vector3(x1 + 1.0, yf + (w0 + w1) * 0.5, -pw * 0.5 + pw * k / n), "steel")
	for k in 6:       # (its lamps down the outer wall)
		put.call(Vector3(0.6, h - w1 - 6.0, 1.2), Vector3(x1 + 2.2, yf + w1 + 3.0 + (h - w1 - 6.0) * 0.5, -pw * 0.45 + pw * 0.9 * k / 5.0), "lights")
	_glass.append([centre + b * Vector3(x1 + 1.0, yf + (w0 + w1) * 0.5, 0), b, Vector2(pw, w1 - w0)])


## A landing pad: its deck (the lift), its rim lights, its number, and the
## shutters that close its shaft: slats stacked on the platform each side
## (`margin` deep), sliding out over the hole, one under another, to meet in
## the middle (set_hatch).
func _pad(id: int, at: Vector3, size: float, yaw: float, margin := 30.0) -> void:
	var deck := _node(_box(Vector3(size, 2.0, size)), _mats["pad"], at - Vector3(0, 1.0, 0))
	deck.name = "Pad%d" % id
	deck.set_meta("keep", true)
	deck.rotation.y = yaw
	# (its axis painted on it, a chevron at its top end - toward the station: where a ship's nose goes)
	var axis := MeshInstance3D.new()
	axis.mesh = _box(Vector3(size * 0.7, 0.06, 1.4))
	axis.material_override = _mats["glow"]
	axis.position = Vector3(size * 0.05, 1.03, 0)
	deck.add_child(axis)
	for sz in [-1.0, 1.0]:
		var chev := MeshInstance3D.new()
		chev.mesh = _box(Vector3(size * 0.16, 0.06, 1.4))
		chev.material_override = _mats["glow"]
		chev.position = Vector3(-size * 0.34 + size * 0.055, 1.03, sz * size * 0.055)
		chev.rotation.y = sz * PI * 0.25
		deck.add_child(chev)
	var glows: Array = []
	for e in 4:
		var a := yaw + e * PI * 0.5
		var d := Vector3(cos(a), 0, -sin(a))
		var strip := _node(_box(Vector3(size * 0.96, 0.6, 2.0)), _mats["glow"], at + d.cross(Vector3.UP) * (size * 0.5 + 1.6) + Vector3(0, 0.3, 0))
		strip.rotation.y = a
		strip.set_meta("group", "pad%d" % id)
		glows.append(strip)
	var l := Label3D.new()
	l.text = str(id)
	l.font_size = 128             # (not 512: sixteen times the glyphs' pixels to make - a 15 ms frame at the first station)
	l.pixel_size = size / 350.0
	l.position = at + Vector3(0, 0.6, 0)
	l.rotation = Vector3(-PI * 0.5, yaw + PI * 0.5, 0)   # (read coming in from outside)
	l.modulate = Color(1, 1, 1, 0.8)
	add_child(l)
	# The shutters: n slats a side, telescoping (stacked when open, side by side shut) -
	# instances of one mesh for the whole station (_shutters), placed by set_hatch.
	var slats: Array = []
	var half := size * 0.5 + 0.5
	var n := maxi(1, ceili(half / maxf(margin - 5.0, 8.0)))
	var sl := half / n + 1.5
	var b := Basis(Vector3.UP, yaw)
	for sx in [-1.0, 1.0]:
		for j in n:
			# {open (x, y), shut (x, y) - pad space: x across the platform's depth, y over its top; size; lit edge}
			slats.append({"i": _slat_n, "open": Vector2(sx * (half + 1.0 + sl * 0.5), 0.8 + j * 1.25),
				"shut": Vector2(sx * (half - (j + 0.5) * (half / n)), 0.6 + (j % 2) * 0.3), "basis": b,
				"size": Vector3(sl, 1.0, size + 3.0), "edge": _edge_n if j == n - 1 else -1, "side": sx, "j": j, "n": n})
			_slat_n += 1
			if j == n - 1:
				_edge_n += 1
	var p := {"id": id, "at": at, "size": size, "owner": null, "glows": glows, "yaw": yaw, "deck": deck, "label": l, "slats": slats}
	pads.append(p)


## Its guns: a heavy turret at each platform's outer corners - a drum on the
## deck, a head that turns (armoured, twin long barrels) - in the empire's look.
static var _gun_meshes: Array = []


static func gun_meshes() -> Array:
	if _gun_meshes.is_empty():
		var m := EmpireKit.Mesher.new()
		m.cyl(Vector3.ZERO, Vector3(0, 2.6, 0), 5.2, 4.6, EmpireKit.IRON, 16)
		m.cyl(Vector3(0, 2.6, 0), Vector3(0, 3.1, 0), 4.7, 4.7, EmpireKit.ACCENT, 16)
		m.cyl(Vector3(0, 0.6, 0), Vector3(0, 0.9, 0), 5.3, 5.3, EmpireKit.LAMP, 16, false)
		var base := m.commit()
		var h := EmpireKit.Mesher.new()
		h.boxat(Vector3(6.4, 3.4, 7.0), Vector3(0, 0, 0.6), EmpireKit.MAIN)
		h.boxat(Vector3(5.6, 1.0, 6.0), Vector3(0, 2.1, 0.8), EmpireKit.ACCENT)
		h.boxat(Vector3(6.6, 0.3, 0.3), Vector3(0, 1.0, -2.95), EmpireKit.GOLD)
		for sx in [-1.2, 1.2]:
			h.cyl(Vector3(sx, 0.2, -2.6), Vector3(sx, 0.2, -16.0), 0.55, 0.42, EmpireKit.STEEL, 10)
			h.cyl(Vector3(sx, 0.2, -16.0), Vector3(sx, 0.2, -17.2), 0.62, 0.62, EmpireKit.IRON, 10)
			h.disc(Vector3(sx, 0.2, -17.25), Vector3(0, 0, -1), Vector3.UP, 0.4, EmpireKit.LAMP, 10)
		h.boxat(Vector3(1.4, 0.8, 1.6), Vector3(2.4, 1.9, 2.4), EmpireKit.SCREEN)
		_gun_meshes = [base, h.commit()]
	return _gun_meshes


func _turrets() -> void:
	var ms := gun_meshes()
	var mat := EmpireKit.mat("station", _emp)
	for pf in platforms:
		var b := Basis(Vector3.UP, float(pf["yaw"]))
		for sz in [-1.0, 1.0]:
			var at: Vector3 = (pf["centre"] as Vector3) + b * Vector3(float(pf["pd"]) * 0.5 - 9.0, 12.0, sz * (float(pf["pw"]) * 0.5 - 9.0))
			var t := Node3D.new()
			t.name = "Gun%d" % turrets.size()
			t.position = at
			add_child(t)
			var base := MeshInstance3D.new()
			base.mesh = ms[0]
			base.material_override = mat
			base.visibility_range_end = 9000.0
			t.add_child(base)
			var head := MeshInstance3D.new()
			head.mesh = ms[1]
			head.material_override = mat
			head.position = Vector3(0, 5.0, 0)
			head.rotation.y = float(pf["yaw"]) - PI * 0.5 + sz * 0.4   # (resting: out over the platform's edge)
			head.visibility_range_end = 9000.0
			t.add_child(head)
			turrets.append(t)


## Every pad's shutter slats: one MultiMesh (and one of their lit edges), all open.
var _slat_n := 0
var _edge_n := 0
var _slats: MultiMesh
var _edges: MultiMesh


func _shutters() -> void:
	_slats = MultiMesh.new()
	_slats.transform_format = MultiMesh.TRANSFORM_3D
	_slats.mesh = _box(Vector3.ONE)
	_slats.instance_count = _slat_n
	_edges = MultiMesh.new()
	_edges.transform_format = MultiMesh.TRANSFORM_3D
	_edges.mesh = _box(Vector3.ONE)
	_edges.instance_count = _edge_n
	for mm in [[_slats, _mats["dark"], "Shutters"], [_edges, _mats["glow"], "ShutterEdges"]]:
		var mi := MultiMeshInstance3D.new()
		mi.name = mm[2]
		mi.multimesh = mm[0]
		mi.material_override = mm[1]
		add_child(mi)
	for p in pads:
		set_hatch(p, 0.0)


## The pad's shutters: open (0) - stacked beside it - to shut (1), sliding over
## its shaft, the far ones first out of the stack.
func set_hatch(p: Dictionary, k: float) -> void:
	if _slats == null:
		return
	for e in p["slats"]:
		var n: int = e["n"]
		var j: int = e["j"]
		var kj := smoothstep(0.0, 1.0, clampf(k * 1.4 - (n - 1 - j) * 0.4 / n, 0.0, 1.0))
		var o: Vector2 = e["open"]
		var c: Vector2 = e["shut"]
		var y := lerpf(o.y, c.y, smoothstep(0.6, 1.0, kj))   # (along at its stack's height, down into place at the end)
		var b: Basis = e["basis"]
		var at: Vector3 = (p["at"] as Vector3) + b * Vector3(lerpf(o.x, c.x, kj), y, 0)
		var sz: Vector3 = e["size"]
		_slats.set_instance_transform(int(e["i"]), Transform3D(b.scaled_local(sz), at))
		if int(e["edge"]) >= 0:
			var ea := at + b * Vector3(-float(e["side"]) * sz.x * 0.5, 0.3, 0)
			_edges.set_instance_transform(int(e["edge"]), Transform3D(b.scaled_local(Vector3(0.8, 0.5, sz.z)), ea))


## The pad's lift: its deck (and the ship on it) `depth` metres down.
func lower_pad(p: Dictionary, depth: float) -> void:
	(p["deck"] as Node3D).position = (p["at"] as Vector3) - Vector3(0, 1.0 + depth, 0)
	(p["label"] as Node3D).position = (p["at"] as Vector3) + Vector3(0, 0.6 - depth, 0)


## A pad free for a ship `length` long (the smallest that takes it), or {}.
func free_pad(length: float, near := Vector3.ZERO) -> Dictionary:
	var best := {}
	for p in pads:
		if p["owner"] != null and is_instance_valid(p["owner"]):
			continue
		if float(p["size"]) < length * 1.15:
			continue
		if best.is_empty() or float(p["size"]) < float(best["size"]) or (float(p["size"]) == float(best["size"]) and to_global(p["at"]).distance_to(near) < to_global(best["at"]).distance_to(near)):
			best = p
	return best


## A platform's port in the station's space: its floor's middle under the
## platform, x out, z along its pads (CosmosHangar's frame).
func port_transform(i: int) -> Transform3D:
	var pf: Dictionary = platforms[i]
	return Transform3D(Basis(Vector3.UP, float(pf["yaw"])), (pf["centre"] as Vector3) + Vector3(0, PORT_FLOOR, 0))


## The pad's top, as a transform in the world (its up: the station's).
func pad_transform(p: Dictionary) -> Transform3D:
	var b := global_basis * Basis(Vector3.UP, float(p["yaw"]))
	return Transform3D(b, to_global(p["at"]))


## Lights a pad (assigned to you) or dims it.
func light_pad(p: Dictionary, on: bool) -> void:
	for g: MeshInstance3D in p.get("glows", []):
		if is_instance_valid(g):
			g.material_override = _mats["lights"] if on else _mats["glow"]


func _process(_delta: float) -> void:
	if _bake_task >= 0:
		_bake_poll()
	if _finished and _bake_task < 0:
		set_process(false)   # (baked: nothing more to do)


## A solid part (a box, a cylinder: _pb / _pc; the beacon: _ps), its look
## ("hull", "paint", "paint2", "dark", "trim", "steel"; "lights", "glow": lit, not solid).
func _piece(shape: Array, look: String, at: Vector3) -> Part:
	var p := Part.new()
	p.kind = shape[0]
	p.size = shape[1]
	p.seg = shape[2]
	p.look = look
	p.position = at
	_parts.append(p)
	return p


static func _pb(size: Vector3) -> Array:
	return [0, size, 0]


static func _pc(top: float, bottom: float, h: float, seg: int) -> Array:
	return [1, Vector3(top, h, bottom), seg]


static func _ps(r: float) -> Array:
	return [2, Vector3(r, r, r), 0]


## A part that's a node of its own (a pad's deck - its lift moves; its lights - lit for you).
func _node(mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	return mi


## A plain material (lit, or glowing). The first of each kind is kept for the
## run: the engine makes a standard material's shader for its set of features
## and drops it with the last material that has them - made again (a 10+ ms
## frame, and its pipelines with it) at the next scene's first one.
static var _kept := {}


static func _mat(c: Color, metal: float, rough: float, glow := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if glow != Color.BLACK:
		m.emission_enabled = true
		m.emission = glow
	if not _kept.has(glow != Color.BLACK):
		_kept[glow != Color.BLACK] = m
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
