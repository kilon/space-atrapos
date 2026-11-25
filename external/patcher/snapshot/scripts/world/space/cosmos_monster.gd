class_name CosmosMonster
extends Node3D
## A space monster (the 3D game): the 2D game's unique creatures
## (EnemyTypes.MONSTERS) in 3D, met at the system's monster signals - "Unknown
## bio-signature" - Void Leviathan, Cetus, Charybdis, Skylla, the Hydra,
## Cerberus, the Chimera, Echidna, the Minotaur. Each is built from a kit of
## procedural parts (Body: tubes lofted along curves - bodies, necks,
## tentacles, legs, tails - heads with jaws, eyes, horns, crowns, fins, teeth,
## armour bands) on a worker, as ONE mesh, and moves in its shader
## (monster.gdshader): every vertex carries how it sways - its phase along
## its limb, how far, which way (swimming waves, writhing tentacles, beating
## fins, striding legs, a turning vortex) - so a 400 m creature is one draw.
## Head toward -z. Its length is the 2D game's (px) in metres.
##
## It swims about its lair; within SIGHT of you it comes for you, keeping
## its distance, and attacks in patterns of slow glowing orbs (rings round
## its aim with a gap in the middle, fans, a spiral, a bloom) - each
## telegraphed by its glow gathering (CHARGE) - and rams you if you come too
## close. Shields soak hits and come back; at no hull it dies: a bounty, the
## signal done. Hit anywhere along its body (spheres along its spine).

const SIGHT := 3500.0
const CHARGE := 0.9
const PAUSE := 1.8
const ORB_SPEED := 260.0
const SHADER := preload("res://shaders/world/monster.gdshader")
const KINDS := ["void_leviathan", "cetus", "charybdis", "skylla", "hydra", "cerberus", "chimera", "echidna", "minotaur"]

var kind := "void_leviathan"
var cosmos: Node
var label := ""
var length := 300.0
var reach := 60.0              # (the HUD: its rough size)
var shield := 0.0
var max_shield := 0.0
var hull := 900.0
var max_hull := 900.0
var damage := 14.0
var mult := 1.0
var hostile := true
var dead := false
var velocity := Vector3.ZERO
var signal_rec := {}           # the signal it's met at (done when it dies)
var lair := Vector3.ZERO       # (global, kept up with the floating origin by Cosmos)
var color := Color(0.45, 1.0, 0.55)
var built := false
var _spheres: Array = []       # [local centre, radius] along its body (hits)
var _mat: ShaderMaterial
var _task := -1
var _out := {}
var _rng := RandomNumberGenerator.new()
var _since_hit := 99.0
var _next := 2.0               # (the next attack)
var _charge := 0.0
var _pattern := ""
var _spiral := 0.0
var _ram_cd := 0.0
var _swim := 0.0
var _flash := 0.0


func setup(k: String, c: Node, seed: int, sig: Dictionary) -> void:
	kind = k
	cosmos = c
	signal_rec = sig
	_rng.seed = seed
	var info: Dictionary = EnemyTypes.MONSTERS.get(k, {})
	label = str(info.get("name", k.capitalize()))
	length = float(info.get("length", 300.0))
	mult = float(SignalSites.level_info(sig).get("mult", 1.0)) if not sig.is_empty() else 1.0
	max_hull = float(info.get("hull", 900.0)) * mult
	max_shield = float(info.get("shields", 0.0)) * mult
	damage = float(info.get("damage", 14.0)) * mult
	color = info.get("color", color)
	hull = max_hull
	shield = max_shield
	reach = length * 0.3
	name = label.replace(" ", "_")
	add_to_group("cam_solid")
	set_meta("cam_reach", length)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("glow_color", color)
	_mat.set_shader_parameter("speed", 0.9 if length > 400 else 1.1)
	var s := seed
	var col := color
	_task = Jobs.add(func(): _out = Body.make(k, length, col, s), false, "monster")


func poll() -> void:
	if built or _task < 0 or not Jobs.done(_task):
		return
	Jobs.wait(_task)
	_task = -1
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = _out["mesh"]
	mi.material_override = _mat
	mi.extra_cull_margin = length * 0.15   # (it sways out of its bounds)
	add_child(mi)
	_spheres = _out["spheres"]
	_out = {}
	built = true


func _exit_tree() -> void:
	if _task >= 0:
		Jobs.wait(_task)
		_task = -1


func up() -> Vector3:
	return global_basis.y


## A bolt's segment a -> a + dir * L: does it meet the body? (CosmosBolt)
func bolt_hit(a: Vector3, dir: Vector3, L: float) -> bool:
	if global_position.distance_to(a) > length + L:
		return false
	for s in _spheres:
		var c: Vector3 = to_global(s[0])
		var t := clampf((c - a).dot(dir), 0.0, L)
		if (a + dir * t).distance_to(c) < float(s[1]):
			return true
	return false


## How far `p` is inside its body (radius r) - for ramming, and the camera.
func overlap(p: Vector3, r: float) -> float:
	var best := 0.0
	for s in _spheres:
		var d := to_global(s[0]).distance_to(p)
		best = maxf(best, float(s[1]) + r - d)
	return best


func hurt(dmg: float, _from: Variant = null) -> void:
	if dead:
		return
	_since_hit = 0.0
	_flash = 0.4
	var sd := minf(shield, dmg)
	shield -= sd
	hull -= dmg - sd
	if hull <= 0.0:
		dead = true
		if cosmos:
			cosmos.monster_died(self)
		CosmosBoom.at(cosmos, global_position, length * 0.3)
		queue_free()


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if dead or cosmos == null:
		return
	poll()
	_since_hit += delta
	_flash = maxf(0.0, _flash - delta)
	if _since_hit > 3.0 and max_shield > 0.0:
		shield = minf(max_shield, shield + 40.0 * mult * delta)
	var ship: Node3D = cosmos.ship
	var to: Vector3 = ship.global_position - global_position if ship else Vector3.ZERO
	var d := to.length()
	var angry: bool = ship != null and cosmos.walker == null and ship.state == "fly" and not cosmos.docked and d < SIGHT
	var want: Vector3
	var spd: float
	if angry:
		# Keep 0.6-1.2 of its length away, circling; now and then a lunge.
		var keep := length * (0.9 if _pattern == "" else 1.3)
		var side := to.cross(Vector3.UP).normalized()
		want = (to / d * clampf((d - keep) / 300.0, -1.0, 1.0) + side * 0.5).normalized()
		spd = clampf(absf(d - keep) * 0.5, 40.0, 220.0)
		_attack(delta, to, d)
	else:
		# Swimming round its lair.
		_swim += delta * 0.05
		var round := lair + Vector3(cos(_swim), sin(_swim * 0.7) * 0.2, sin(_swim)) * length * 2.0
		want = (round - global_position).normalized()
		spd = 50.0
		_charge = maxf(0.0, _charge - delta)
	var f := -global_basis.z
	var ang := f.angle_to(want)
	if ang > 0.001:
		var axis := f.cross(want)
		if axis.length() < 0.001:
			axis = global_basis.y
		global_basis = (Basis(axis.normalized(), minf(ang, 0.5 * delta)) * global_basis).orthonormalized()
	velocity = velocity.move_toward(-global_basis.z * spd, 60.0 * delta)
	global_position += velocity * delta
	# Ramming: your ship in its body takes it, and is thrown off.
	_ram_cd -= delta
	if ship and built and ship.state == "fly" and _ram_cd <= 0.0:
		var o := overlap(ship.global_position, CosmosShip.HULL_R)
		if o > 0.0:
			_ram_cd = 1.0
			ship.hurt(damage * 3.0, global_position)
			ship.velocity += (ship.global_position - global_position).normalized() * 120.0
	_mat.set_shader_parameter("charge", _charge / CHARGE)
	_mat.set_shader_parameter("flash", _flash)
	_mat.set_shader_parameter("wave", 1.0 + (0.6 if angry else 0.0))


## The attacks: a pattern chosen, its charge (the glow gathering), then its orbs.
func _attack(delta: float, to: Vector3, d: float) -> void:
	if _pattern == "spiral":
		_spiral += delta
		var k := int(_spiral / 0.08)
		if k > int((_spiral - delta) / 0.08):
			var aim := _aim()
			var b := Basis.looking_at(aim, Vector3.UP)
			var a := _spiral * 7.0
			_orb(b * Vector3(cos(a) * 0.35, sin(a) * 0.35, -1.0).normalized())
		if _spiral > 2.2:
			_pattern = ""
			_next = PAUSE
		return
	if _charge > 0.0:
		_charge += delta
		if _charge >= CHARGE:
			_charge = 0.0
			_fire(_pattern, _aim())
		return
	_next -= delta
	if _next <= 0.0 and d < SIGHT * 0.8:
		_pattern = ["ring", "fan", "spiral", "bloom"][_rng.randi() % 4]
		_charge = 0.001


func _fire(p: String, aim: Vector3) -> void:
	var b := Basis.looking_at(aim, Vector3.UP)
	match p:
		"ring":   # (round the aim, a gap in the middle: stay put or slip through)
			for i in 18:
				var a := TAU * i / 18.0
				_orb(b * Vector3(cos(a) * 0.16, sin(a) * 0.16, -1.0).normalized())
		"fan":
			for i in 9:
				_orb(b * Vector3((i - 4) * 0.07, _rng.randf_range(-0.02, 0.02), -1.0).normalized())
		"bloom":
			for i in 40:
				var y := 1.0 - 2.0 * (i + 0.5) / 40.0
				var r := sqrt(1.0 - y * y)
				var a := i * 2.39996
				_orb(Vector3(cos(a) * r, y, sin(a) * r))
		"spiral":
			_spiral = 0.0
			return
	_pattern = ""
	_next = PAUSE * _rng.randf_range(0.8, 1.3)


## Its maw: where the orbs come from.
func _muzzle() -> Vector3:
	return global_position - global_basis.z * length * 0.45


## From its maw to your ship.
func _aim() -> Vector3:
	return (cosmos.ship.global_position - _muzzle()).normalized()


func _orb(dir: Vector3) -> void:
	var from := _muzzle()
	CosmosBolt.fire(cosmos, from, dir, "enemy", damage, true, ORB_SPEED, color)


# --- The body kit (on a worker) ------------------------------------------------------------

class Body:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()      # albedo, a = 1 - metallic (gold: 0)
	var custom := PackedFloat32Array()  # phase, amplitude, glow, group
	var idx := PackedInt32Array()
	var spheres: Array = []
	var rng := RandomNumberGenerator.new()
	# The sway of what's added next: [group, phase at its root, phase along it, amplitude at root, at tip]
	var sway := [0, 0.0, 0.0, 0.0, 0.0]
	var glow := 0.0

	static func make(kind: String, L: float, accent: Color, seed: int) -> Dictionary:
		var b := Body.new()
		b.rng.seed = seed
		b.call("_" + kind, L, accent)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = b.verts
		arr[Mesh.ARRAY_NORMAL] = b.norms
		arr[Mesh.ARRAY_COLOR] = b.cols
		arr[Mesh.ARRAY_CUSTOM0] = b.custom
		arr[Mesh.ARRAY_INDEX] = b.idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		return {"mesh": m, "spheres": b.spheres}

	func _v(p: Vector3, n: Vector3, c: Color, t: float) -> int:
		verts.append(p)
		norms.append(n)
		cols.append(c)
		var amp := lerpf(float(sway[3]), float(sway[4]), pow(t, 1.4))
		custom.append_array([float(sway[1]) + float(sway[2]) * t, amp, glow, float(sway[0])])
		return verts.size() - 1

	## A triangle, wound to face its vertices' normals (Godot: clockwise front).
	func _tri(a: int, b: int, c: int) -> void:
		var n := norms[a] + norms[b] + norms[c]
		if (verts[b] - verts[a]).cross(verts[c] - verts[a]).dot(n) > 0.0:
			idx.append_array([a, c, b])
		else:
			idx.append_array([a, b, c])

	## A tube lofted along `pts` with `radii` (an ellipse: `flat` squashes it
	## along its second axis), `seg` round, closed at its tip; `hit`: spheres
	## along it for bolts.
	func tube(pts0: Array, radii0: Array, seg: int, c: Color, flat := 1.0, hit := false, up_hint := Vector3.UP) -> void:
		# (smoothed: each span of a curve of 4+ points cut in three along a Catmull-Rom spline; more sides round)
		var pts := pts0
		var radii := radii0
		if pts0.size() >= 4:
			pts = []
			radii = []
			var m := pts0.size()
			for i in m - 1:
				var p0: Vector3 = pts0[maxi(i - 1, 0)]
				var p1: Vector3 = pts0[i]
				var p2: Vector3 = pts0[i + 1]
				var p3: Vector3 = pts0[mini(i + 2, m - 1)]
				for k in 3:
					var t := k / 3.0
					pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
					radii.append(lerpf(float(radii0[i]), float(radii0[i + 1]), t))
			pts.append(pts0[m - 1])
			radii.append(radii0[m - 1])
		if seg >= 8:
			seg = int(seg * 1.5)
		var n := pts.size()
		var N := up_hint
		var rings: Array = []
		for i in n:
			var p: Vector3 = pts[i]
			var T: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
			N = (N - T * N.dot(T))
			if N.length() < 0.01:
				N = T.cross(Vector3.RIGHT if absf(T.x) < 0.9 else Vector3.UP)
			N = N.normalized()
			var B := T.cross(N)
			var r: float = radii[i]
			var t := float(i) / (n - 1)
			var ring: Array = []
			for j in seg:
				var a := TAU * j / seg
				var dn := N * cos(a) * flat + B * sin(a)
				var dir := N * cos(a) + B * sin(a)
				ring.append(_v(p + dn * r, dir, c, t))
			rings.append(ring)
			if hit and r > 4.0 and i % (2 if pts0.size() < 4 else 5) == 0:
				spheres.append([p, r * 1.1])
		for i in n - 1:
			for j in seg:
				var a: int = rings[i][j]
				var b: int = rings[i][(j + 1) % seg]
				var cc: int = rings[i + 1][(j + 1) % seg]
				var d: int = rings[i + 1][j]
				_tri(a, b, cc)
				_tri(a, cc, d)
		# Caps: the tip a point beyond, the root a disc.
		var last: Vector3 = pts[n - 1]
		var tdir: Vector3 = (last - (pts[n - 2] as Vector3)).normalized()
		var tip := _v(last + tdir * float(radii[n - 1]) * 0.6, tdir, c, 1.0)
		for j in seg:
			_tri(rings[n - 1][j], rings[n - 1][(j + 1) % seg], tip)
		var first: Vector3 = pts[0]
		var rdir: Vector3 = (first - (pts[1] as Vector3)).normalized()
		var root := _v(first + rdir * float(radii[0]) * 0.3, rdir, c, 0.0)
		for j in seg:
			_tri(rings[0][j], rings[0][(j + 1) % seg], root)

	## A curve from `a` along `dir`, bending by `bend` (each step turns it
	## round `axis`), `n` points `step` apart.
	static func curve(a: Vector3, dir: Vector3, n: int, step: float, bend := 0.0, axis := Vector3.UP, wiggle := 0.0, rng: RandomNumberGenerator = null) -> Array:
		var out: Array = [a]
		var d := dir.normalized()
		var p := a
		for i in n - 1:
			d = d.rotated(axis, bend)
			if rng and wiggle > 0.0:
				d = d.rotated(d.cross(axis).normalized(), rng.randf_range(-wiggle, wiggle))
			p += d * step
			out.append(p)
		return out

	## Radii along n points: from r0 to r1 by a profile (0 straight, 1 swelling in the middle).
	static func radii(n: int, r0: float, r1: float, swell := 0.0) -> Array:
		var out: Array = []
		for i in n:
			var t := float(i) / (n - 1)
			out.append(lerpf(r0, r1, t) * (1.0 + swell * sin(t * PI)))
		return out

	func ball(c: Vector3, r: float, col: Color, seg := 10) -> void:
		var pts: Array = []
		var rr: Array = []
		for i in 7:
			var a := PI * (i + 0.5) / 7.0
			pts.append(c + Vector3(0, 0, -r * cos(a)))
			rr.append(maxf(r * sin(a), r * 0.05))
		tube(pts, rr, seg, col)

	func cone(base: Vector3, tip: Vector3, r: float, col: Color, seg := 6) -> void:
		tube([base, base.lerp(tip, 0.5), tip], [r, r * 0.55, r * 0.06], seg, col)

	## A fin: a thin blade from root (r long along `along`) out to `tip`.
	func fin(root: Vector3, along: Vector3, tip: Vector3, thick: float, col: Color) -> void:
		var a := root
		var b := root + along
		var nrm := along.cross(tip - root).normalized()
		var off := nrm * thick
		var ids := [_v(a + off, nrm, col, 0.0), _v(b + off, nrm, col, 0.0), _v(tip + off, nrm, col, 1.0),
			_v(a - off, -nrm, col, 0.0), _v(b - off, -nrm, col, 0.0), _v(tip - off, -nrm, col, 1.0)]
		_tri(ids[0], ids[1], ids[2])
		_tri(ids[3], ids[4], ids[5])

	## Eyes: two glowing balls either side of `at` (across `side`).
	func eyes(at: Vector3, side: Vector3, r: float, accent: Color) -> void:
		var g := glow
		glow = 2.5
		for s in [-1.0, 1.0]:
			ball(at + side * s, r, accent.lightened(0.3), 6)
		glow = g

	## A head along `dir` from `at`: a skull tapering to the snout, a lower
	## jaw, eyes; `horns` curving back; teeth.
	func head(at: Vector3, dir: Vector3, size: float, skin: Color, accent: Color, horns := 0, jaw := true, snout := 1.0) -> void:
		var d := dir.normalized()
		var side := d.cross(Vector3.UP).normalized()
		if side.length() < 0.5:
			side = Vector3.RIGHT
		var up := side.cross(d).normalized()
		var pts := [at, at + d * size * 0.5, at + d * size * 1.0 * snout, at + d * size * 1.5 * snout]
		tube(pts, [size * 0.45, size * 0.5, size * 0.38, size * 0.2], 10, skin, 0.8, true, up)
		if jaw:
			var jp := [at - up * size * 0.2, at + d * size * 0.7 * snout - up * size * 0.3, at + d * size * 1.35 * snout - up * size * 0.25]
			tube(jp, [size * 0.3, size * 0.26, size * 0.12], 8, skin.darkened(0.25), 0.6, false, up)
			for k in 4:
				for s in [-1.0, 1.0]:
					var tb: Vector3 = at + d * size * (0.6 + k * 0.22) * snout + side * s * size * 0.22 - up * size * 0.08
					cone(tb, tb - up * size * 0.18, size * 0.05, Color(0.92, 0.9, 0.82), 5)
		eyes(at + d * size * 0.55 + up * size * 0.25, side * size * 0.3, size * 0.09, accent)
		for k in horns:
			var s := -1.0 if k % 2 == 0 else 1.0
			var hb := at + up * size * 0.35 + side * s * size * (0.25 + 0.1 * (k / 2))
			var hp := curve(hb, (up + side * s * 0.6 - d * 0.4).normalized(), 6, size * 0.3, -0.25, side * s)
			tube(hp, radii(6, size * 0.1, size * 0.02), 6, Color(0.85, 0.78, 0.6).darkened(0.2))

	## A crown: a gold band with spikes round `at` (its axis `up`).
	func crown(at: Vector3, up: Vector3, r: float) -> void:
		var gold := Color(0.95, 0.72, 0.25, 0.0)
		var side := up.cross(Vector3.FORWARD).normalized()
		if side.length() < 0.5:
			side = Vector3.RIGHT
		var fwd := side.cross(up)
		var pts: Array = []
		for k in 13:
			var a := TAU * k / 12.0
			pts.append(at + (side * cos(a) + fwd * sin(a)) * r)
		tube(pts, radii(13, r * 0.12, r * 0.12), 6, gold)
		for k in 8:
			var a := TAU * k / 8.0
			var b2: Vector3 = at + (side * cos(a) + fwd * sin(a)) * r
			cone(b2, b2 + up * r * 0.6, r * 0.1, gold, 5)

	## Armour bands round a body tube (rings at intervals along it).
	func bands(pts: Array, rr: Array, every: int, col: Color) -> void:
		for i in range(1, pts.size() - 1, every):
			var p0: Vector3 = pts[i]
			var p1: Vector3 = (pts[i + 1] as Vector3)
			var r: float = rr[i] * 1.06
			tube([p0, p0.lerp(p1, 0.35)], [r, r], 12, col)

	func _sway(group: int, ph0: float, ph_k: float, a0: float, a1: float) -> void:
		sway = [group, ph0, ph_k, a0, a1]

	# --- The creatures -----------------------------------------------------------------

	## Void Leviathan: a vast whale-serpent swimming between stars - plated
	## body, glowing veins, two pairs of fins, tentacles round its maw.
	func _void_leviathan(L: float, accent: Color) -> void:
		var skin := Color(0.16, 0.2, 0.26)
		var n := 18
		var spine := curve(Vector3(0, 0, -L * 0.5), Vector3(0, 0, 1), n, L / (n - 1))
		var rr: Array = []
		for i in n:
			var t := float(i) / (n - 1)
			rr.append(L * 0.11 * (0.55 + 0.6 * sin(clampf(t * 1.25, 0.0, 1.0) * PI)) * (1.0 - t * 0.8))
		_sway(1, 0.0, 5.0, 0.0, L * 0.06)
		tube(spine, rr, 16, skin, 0.75, true)
		bands(spine, rr, 2, Color(0.28, 0.3, 0.34, 0.6))
		glow = 1.6
		var vein: Array = []   # (along its back)
		for i in range(1, n - 2):
			vein.append((spine[i] as Vector3) + Vector3(0, float(rr[i]) * 0.72, 0))
		tube(vein, radii(vein.size(), L * 0.008, L * 0.004), 5, accent)
		glow = 0.0
		var fin_c := skin.lightened(0.1)
		for pair in 2:
			var z := -L * 0.25 + pair * L * 0.4
			var r: float = rr[int((z / L + 0.5) * (n - 1))]
			for s in [-1.0, 1.0]:
				_sway(2, pair * 1.5, 1.0, 0.0, L * 0.07)
				fin(Vector3(s * r * 0.7, -r * 0.2, z), Vector3(0, 0, L * 0.12), Vector3(s * (r + L * 0.22), -r * 0.5, z + L * 0.14), L * 0.005, fin_c)
		_sway(3, 0.0, 4.0, 0.0, L * 0.05)
		for k in 6:
			var a := TAU * k / 6.0
			var base := Vector3(cos(a) * rr[0] * 0.6, sin(a) * rr[0] * 0.5, -L * 0.5)
			var tp := curve(base, Vector3(cos(a) * 0.4, sin(a) * 0.4, -1.0), 10, L * 0.035, 0.05, Vector3(-sin(a), cos(a), 0), 0.15, rng)
			sway[1] = k * 1.1
			tube(tp, radii(10, L * 0.018, L * 0.003), 6, skin.lightened(0.15))
		_sway(0, 0.0, 0.0, 0.0, 0.0)
		eyes(Vector3(0, rr[1] * 0.3, -L * 0.42), Vector3(rr[1] * 0.8, 0, 0), L * 0.012, accent)

	## Cetus: an armoured whale-serpent - long, banded in plates, a great
	## head with jaws, a row of dorsal fins, a tail fluke.
	func _cetus(L: float, accent: Color) -> void:
		var skin := Color(0.18, 0.26, 0.36)
		var n := 24
		var spine := curve(Vector3(0, 0, -L * 0.42), Vector3(0, 0, 1), n, L * 0.85 / (n - 1), 0.0)
		var rr: Array = []
		for i in n:
			var t := float(i) / (n - 1)
			rr.append(L * 0.075 * (1.0 - t * 0.85) + L * 0.01)
		_sway(1, 0.0, 6.0, L * 0.01, L * 0.08)
		tube(spine, rr, 14, skin, 0.85, true)
		bands(spine, rr, 2, Color(0.55, 0.5, 0.42, 0.5))
		for i in range(2, n - 4, 2):
			var p: Vector3 = spine[i]
			sway[1] = 6.0 * float(i) / (n - 1)
			fin(p + Vector3(0, rr[i] * 0.8, -L * 0.01), Vector3(0, 0, L * 0.03), p + Vector3(0, rr[i] + L * 0.05, L * 0.02), L * 0.003, Color(0.3, 0.42, 0.55))
		var tail: Vector3 = spine[n - 1]
		for s in [-1.0, 1.0]:
			fin(tail, Vector3(0, 0, L * 0.02), tail + Vector3(s * L * 0.12, 0, L * 0.08), L * 0.004, skin.lightened(0.1))
		_sway(0, 0.0, 0.0, 0.0, 0.0)
		head(Vector3(0, 0, -L * 0.4), Vector3(0, 0, -1), L * 0.12, skin.lightened(0.05), accent, 0, true, 1.0)

	## Charybdis: the whirlpool - a ring of flesh and teeth round a turning
	## vortex, tentacles writhing at its rim. (It faces -z: the maw.)
	func _charybdis(L: float, accent: Color) -> void:
		var skin := Color(0.2, 0.3, 0.32)
		var R := L * 0.3
		var ring: Array = []
		for k in 25:
			var a := TAU * k / 24.0
			ring.append(Vector3(cos(a) * R, sin(a) * R, 0))
		_sway(0, 0.0, 0.0, 0.0, 0.0)
		tube(ring, radii(25, L * 0.07, L * 0.07), 12, skin, 1.0, true, Vector3.BACK)
		for k in 36:   # (the teeth, pointing in)
			var a := TAU * k / 36.0
			var b := Vector3(cos(a), sin(a), 0) * (R - L * 0.05) + Vector3(0, 0, -L * 0.03)
			cone(b, b - Vector3(cos(a), sin(a), 0) * L * 0.07 - Vector3(0, 0, L * 0.02), L * 0.012, Color(0.9, 0.88, 0.8), 5)
		# The vortex: a spinning disc of glowing arms.
		_sway(4, 0.0, 0.0, 0.0, 0.0)
		glow = 1.2
		for arm in 5:
			var pts: Array = []
			for k in 16:
				var t := k / 15.0
				var a := arm * TAU / 5.0 + t * 4.0
				pts.append(Vector3(cos(a), sin(a), 0) * R * 0.85 * (1.0 - t) + Vector3(0, 0, L * 0.05 * t))
			tube(pts, radii(16, L * 0.03, L * 0.005), 5, accent.darkened(0.2))
		glow = 0.0
		# A body behind: a funnel narrowing away.
		_sway(1, 0.0, 3.0, 0.0, L * 0.03)
		tube([Vector3(0, 0, L * 0.02), Vector3(0, 0, L * 0.25), Vector3(0, 0, L * 0.5)], [R * 0.9, R * 0.5, R * 0.1], 14, skin.darkened(0.2), 1.0, true)
		_sway(3, 0.0, 4.0, 0.0, L * 0.06)
		for k in 12:
			var a := TAU * k / 12.0
			var base := Vector3(cos(a), sin(a), 0) * (R + L * 0.04)
			var tp := curve(base, Vector3(cos(a), sin(a), -0.6), 10, L * 0.04, 0.08, Vector3(-sin(a), cos(a), 0), 0.2, rng)
			sway[1] = k * 0.9
			tube(tp, radii(10, L * 0.022, L * 0.004), 6, skin.lightened(0.1))

	## Skylla: a sea witch crowned in gold, rising from eight great tentacles.
	func _skylla(L: float, accent: Color) -> void:
		var skin := Color(0.45, 0.3, 0.4)
		var body := Color(0.7, 0.55, 0.6)
		_sway(1, 0.0, 1.0, 0.0, L * 0.01)
		ball(Vector3(0, 0, 0), L * 0.1, skin, 12)
		spheres.append([Vector3.ZERO, L * 0.12])
		_sway(3, 0.0, 4.5, 0.0, L * 0.07)
		for k in 8:
			var a := TAU * k / 8.0
			var base := Vector3(cos(a) * L * 0.06, -L * 0.04, sin(a) * L * 0.06)
			var tp := curve(base, Vector3(cos(a), -0.7, sin(a)), 14, L * 0.035, 0.12, Vector3(-sin(a), 0, cos(a)), 0.08, rng)
			sway[1] = k * 0.8
			tube(tp, radii(14, L * 0.03, L * 0.004), 8, skin, 1.0, true)
		# The witch: a torso, arms, a head with flowing hair, a gold crown.
		_sway(1, 0.0, 1.0, 0.0, L * 0.01)
		var torso := [Vector3(0, L * 0.06, 0), Vector3(0, L * 0.14, 0), Vector3(0, L * 0.22, 0)]
		tube(torso, [L * 0.05, L * 0.04, L * 0.045], 10, body, 0.7, true, Vector3.FORWARD)
		for s in [-1.0, 1.0]:
			_sway(3, s, 1.0, 0.0, L * 0.02)
			var arm := curve(Vector3(s * L * 0.05, L * 0.21, 0), Vector3(s, 0.3, -0.4), 6, L * 0.03, 0.15, Vector3(0, 0, s))
			tube(arm, radii(6, L * 0.014, L * 0.008), 6, body)
		_sway(0, 0.0, 0.0, 0.0, 0.0)
		ball(Vector3(0, L * 0.27, 0), L * 0.035, body, 10)
		eyes(Vector3(0, L * 0.275, -L * 0.03), Vector3(L * 0.012, 0, 0), L * 0.005, accent)
		crown(Vector3(0, L * 0.3, 0), Vector3.UP, L * 0.03)
		_sway(3, 0.0, 2.0, 0.0, L * 0.02)
		for k in 6:   # (hair)
			var a := PI * 0.2 + PI * 0.6 * k / 5.0
			var hp := curve(Vector3(cos(a) * L * 0.03, L * 0.28, sin(a) * L * 0.03), Vector3(cos(a) * 0.3, -1.0, 0.6), 6, L * 0.025, 0.1, Vector3.RIGHT)
			tube(hp, radii(6, L * 0.008, L * 0.002), 5, Color(0.12, 0.06, 0.1))

	## The Hydra: eight long necks rising from a knot of coils, each a serpent head.
	func _hydra(L: float, accent: Color) -> void:
		var skin := Color(0.2, 0.36, 0.16)
		_sway(1, 0.0, 3.0, 0.0, L * 0.02)
		var coil: Array = []
		for k in 30:
			var t := k / 29.0
			var a := t * TAU * 2.0
			coil.append(Vector3(cos(a) * L * 0.12, -L * 0.05 + t * L * 0.08, sin(a) * L * 0.12 + L * 0.1))
		tube(coil, radii(30, L * 0.06, L * 0.03, 0.3), 12, skin, 1.0, true)
		var tail := curve(coil[29], Vector3(0, -0.3, 1), 10, L * 0.04, 0.1, Vector3.UP)
		_sway(1, 0.0, 4.0, 0.0, L * 0.05)
		tube(tail, radii(10, L * 0.03, L * 0.004), 8, skin)
		for k in 8:
			var a := -PI * 0.5 + (k - 3.5) * 0.28
			var base := Vector3(cos(a) * L * 0.06, L * 0.02, L * 0.06 + sin(a) * L * 0.06)
			var dir := Vector3((k - 3.5) * 0.18, 0.9, -0.8).normalized()
			var neck := curve(base, dir, 10, L * 0.035, -0.07, Vector3(1, 0, 0), 0.05, rng)
			_sway(3, k * 0.9, 3.0, 0.0, L * 0.04)
			tube(neck, radii(10, L * 0.025, L * 0.016), 8, skin.lightened(0.05), 1.0, true)
			var hd: Vector3 = neck[9]
			sway = [3, k * 0.9 + 3.0, 0.0, L * 0.04, L * 0.04]
			head(hd, ((neck[9] as Vector3) - (neck[8] as Vector3)).normalized().lerp(Vector3(0, 0, -1), 0.6), L * 0.03, skin.lightened(0.1), accent, 2 if k % 3 == 0 else 0)

	## A quadruped (Cerberus, the Chimera): a long body on four legs, a chest,
	## a tail; the legs stride (group 5).
	func _beast(L: float, skin: Color, belly: Color) -> Dictionary:
		var n := 8
		var spine := curve(Vector3(0, L * 0.02, -L * 0.25), Vector3(0, 0, 1), n, L * 0.45 / (n - 1))
		var rr := radii(n, L * 0.1, L * 0.065, 0.15)
		_sway(1, 0.0, 1.0, 0.0, L * 0.008)
		tube(spine, rr, 14, skin, 0.9, true)
		for leg in 4:
			var front := leg < 2
			var s := -1.0 if leg % 2 == 0 else 1.0
			var hip := Vector3(s * L * 0.06, -L * 0.03, (-L * 0.2 if front else L * 0.16))
			_sway(5, (0.0 if front else PI) + (0.0 if s < 0 else PI * 0.5), 0.5, 0.0, L * 0.04)
			var pts := [hip, hip + Vector3(0, -L * 0.1, -L * 0.01 if front else L * 0.03), hip + Vector3(0, -L * 0.2, -L * 0.02), hip + Vector3(0, -L * 0.21, -L * 0.05)]
			tube(pts, [L * 0.045, L * 0.03, L * 0.022, L * 0.025], 8, skin.darkened(0.1), 1.0, true)
			for c in 3:   # (claws)
				var cb: Vector3 = pts[3] + Vector3((c - 1) * L * 0.01, 0, -L * 0.012)
				cone(cb, cb + Vector3(0, -L * 0.012, -L * 0.02), L * 0.005, Color(0.15, 0.12, 0.1), 4)
		_sway(1, 0.0, 3.0, 0.0, L * 0.05)
		var tail := curve(spine[n - 1], Vector3(0, 0.4, 1), 8, L * 0.035, -0.12, Vector3.RIGHT)
		_sway(0, 0.0, 0.0, 0.0, 0.0)
		return {"spine": spine, "rr": rr, "tail": tail}

	## Cerberus: the three-headed hound, armoured in gold.
	func _cerberus(L: float, accent: Color) -> void:
		var skin := Color(0.05, 0.045, 0.045)
		var b := _beast(L, skin, skin)
		_sway(1, 0.0, 3.0, 0.0, L * 0.05)
		tube(b["tail"], radii(8, L * 0.02, L * 0.004), 6, skin)
		var chest: Vector3 = b["spine"][0]
		bands(b["spine"], b["rr"], 3, Color(0.9, 0.7, 0.25, 0.0))
		for k in 3:
			var s := float(k - 1)
			var base := chest + Vector3(s * L * 0.05, L * 0.04, -L * 0.03)
			var neck := curve(base, Vector3(s * 0.5, 0.8, -0.6), 5, L * 0.035, 0.0, Vector3.RIGHT)
			_sway(3, k * 1.7, 1.0, 0.0, L * 0.02)
			tube(neck, radii(5, L * 0.035, L * 0.03), 8, skin, 1.0, true)
			sway = [3, k * 1.7 + 1.0, 0.0, L * 0.02, L * 0.02]
			head(neck[4], Vector3(s * 0.2, -0.1, -1), L * 0.045, skin, accent, 0, true, 1.2)
			for e in [-1.0, 1.0]:   # (ears)
				var eb: Vector3 = (neck[4] as Vector3) + Vector3(e * L * 0.018, L * 0.02, 0)
				cone(eb, eb + Vector3(e * L * 0.008, L * 0.03, L * 0.01), L * 0.008, skin, 4)
			crown((neck[2] as Vector3), (neck[3] as Vector3 - (neck[2] as Vector3)).normalized(), L * 0.04)

	## The Chimera: a lion in front (a mane), a goat's head rising from its back,
	## a serpent for a tail.
	func _chimera(L: float, accent: Color) -> void:
		var skin := Color(0.62, 0.42, 0.2)
		var b := _beast(L, skin, skin.lightened(0.2))
		var chest: Vector3 = b["spine"][0]
		_sway(3, 0.0, 1.0, 0.0, L * 0.01)
		head(chest + Vector3(0, L * 0.06, -L * 0.06), Vector3(0, -0.15, -1), L * 0.06, skin, accent, 0, true, 0.9)
		var mane := Color(0.35, 0.2, 0.08)
		for k in 18:   # (the mane: spikes round the lion's neck)
			var a := TAU * k / 18.0
			var mb := chest + Vector3(cos(a) * L * 0.07, L * 0.05 + sin(a) * L * 0.07, -L * 0.04)
			cone(mb, mb + Vector3(cos(a), sin(a), 0.6).normalized() * L * 0.06, L * 0.015, mane, 4)
		# The goat: a neck from the back, its head, its curving horns.
		var back: Vector3 = b["spine"][4]
		var gneck := curve(back + Vector3(0, L * 0.05, 0), Vector3(0, 1, -0.3), 5, L * 0.03, 0.0, Vector3.RIGHT)
		_sway(3, 2.0, 1.0, 0.0, L * 0.02)
		tube(gneck, radii(5, L * 0.025, L * 0.02), 8, Color(0.55, 0.5, 0.45), 1.0, true)
		head(gneck[4], Vector3(0, -0.3, -1), L * 0.035, Color(0.6, 0.56, 0.5), accent, 2, true, 1.1)
		# The serpent tail, with its own head.
		var tail: Array = b["tail"]
		_sway(1, 0.0, 3.0, 0.0, L * 0.05)
		tube(tail, radii(8, L * 0.022, L * 0.012), 6, Color(0.25, 0.4, 0.15))
		sway = [1, 3.0, 0.0, L * 0.05, L * 0.05]
		head(tail[7], ((tail[7] as Vector3) - (tail[6] as Vector3)).normalized(), L * 0.02, Color(0.25, 0.4, 0.15), accent)

	## Echidna: half woman, half serpent, coiled in gold-banded scales.
	func _echidna(L: float, accent: Color) -> void:
		var scales := Color(0.22, 0.38, 0.12)
		var body := Color(0.75, 0.6, 0.5)
		var coil: Array = []
		for k in 28:
			var t := k / 27.0
			var a := t * TAU * 1.6
			coil.append(Vector3(cos(a) * L * 0.14 * (1.0 - t * 0.4), -L * 0.12 + t * L * 0.1, sin(a) * L * 0.14 * (1.0 - t * 0.4)))
		coil.reverse()
		_sway(1, 0.0, 4.0, 0.0, L * 0.02)
		var rr := radii(28, L * 0.06, L * 0.012)
		tube(coil, rr, 12, scales, 0.9, true)
		bands(coil, rr, 3, Color(0.9, 0.7, 0.25, 0.0))
		var top: Vector3 = coil[0]
		_sway(1, 0.0, 1.0, 0.0, L * 0.01)
		var torso := [top, top + Vector3(0, L * 0.08, 0), top + Vector3(0, L * 0.16, 0)]
		tube(torso, [L * 0.06, L * 0.045, L * 0.05], 10, body, 0.7, true, Vector3.FORWARD)
		for s in [-1.0, 1.0]:
			_sway(3, s, 1.0, 0.0, L * 0.02)
			var arm := curve(top + Vector3(s * L * 0.055, L * 0.15, 0), Vector3(s, 0.2, -0.5), 6, L * 0.03, 0.15, Vector3(0, 0, s))
			tube(arm, radii(6, L * 0.016, L * 0.009), 6, body)
		_sway(0, 0.0, 0.0, 0.0, 0.0)
		ball(top + Vector3(0, L * 0.21, 0), L * 0.04, body, 10)
		eyes(top + Vector3(0, L * 0.215, -L * 0.035), Vector3(L * 0.014, 0, 0), L * 0.006, accent)
		crown(top + Vector3(0, L * 0.245, 0), Vector3.UP, L * 0.03)

	## The Minotaur: the bull-headed giant crowned in bronze, his crest aglow.
	func _minotaur(L: float, accent: Color) -> void:
		var skin := Color(0.35, 0.2, 0.14)
		var bronze := Color(0.8, 0.5, 0.25, 0.0)
		_sway(1, 0.0, 1.0, 0.0, L * 0.006)
		var torso := [Vector3(0, -L * 0.05, 0), Vector3(0, L * 0.05, 0), Vector3(0, L * 0.14, 0)]
		tube(torso, [L * 0.07, L * 0.09, L * 0.1], 12, skin, 0.7, true, Vector3.FORWARD)
		bands(torso, [L * 0.07, L * 0.09, L * 0.1], 1, bronze)
		for s in [-1.0, 1.0]:
			_sway(5, 0.0 if s < 0 else PI, 0.5, 0.0, L * 0.03)
			var leg := [Vector3(s * L * 0.045, -L * 0.07, 0), Vector3(s * L * 0.05, -L * 0.17, -L * 0.01), Vector3(s * L * 0.05, -L * 0.27, 0)]
			tube(leg, [L * 0.04, L * 0.03, L * 0.028], 8, skin, 1.0, true)
			cone(leg[2], (leg[2] as Vector3) + Vector3(0, -L * 0.02, -L * 0.02), L * 0.03, Color(0.1, 0.08, 0.06), 6)
			_sway(3, 1.0 if s < 0 else 2.5, 1.0, 0.0, L * 0.025)
			var arm := curve(Vector3(s * L * 0.11, L * 0.12, 0), Vector3(s * 0.4, -0.8, -0.4), 6, L * 0.035, 0.0, Vector3.RIGHT)
			tube(arm, radii(6, L * 0.03, L * 0.022), 8, skin, 1.0, true)
		_sway(1, 0.0, 1.0, 0.0, L * 0.006)
		head(Vector3(0, L * 0.18, L * 0.01), Vector3(0, -0.2, -1), L * 0.07, skin.darkened(0.2), accent, 0, true, 1.0)
		var hc := Vector3(0, L * 0.21, 0)
		for s in [-1.0, 1.0]:   # (the bull's great horns)
			var hp := curve(hc + Vector3(s * L * 0.04, 0, 0), Vector3(s, 0.3, -0.2), 7, L * 0.025, 0.25 * s, Vector3(0, 0, 1))
			tube(hp, radii(7, L * 0.016, L * 0.002), 6, Color(0.9, 0.85, 0.7))
		crown(hc + Vector3(0, L * 0.02, 0), Vector3.UP, L * 0.04)
		glow = 2.0
		ball(hc + Vector3(0, L * 0.05, -L * 0.01), L * 0.012, accent, 8)
		glow = 0.0
