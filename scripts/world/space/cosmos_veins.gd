class_name CosmosVeins
extends Node3D
## Mineral veins in a world's ground (a child of Cosmos): ore bodies buried a few
## metres down - a winding chain of a mineral, far richer than a deposit on the
## surface - found round you a cell at a time (on a worker, as CosmosDeposits'),
## mined by digging into them with the terrain digger (CosmosDeposits._dig: each
## carve that cuts into one yields its ore). The scanner (CosmosSandbox.scan)
## shows the ones near you as a ghost through the ground for a minute - where to
## dig. What's left of each is kept in the save (CosmosGame.extra "veins").
## Scanned, each is shown as a hologram through the ground (holo_mesh: its ore body a
## glowing glass tube under a wireframe cage, vein_holo.gdshader) - its 3D shape at a
## glance - for the scan's minute, dimmed by what's left of it. The terrain shader
## knows them too (`vein_*`, sent by _send): the dug ground's walls (the voxels) solid
## ore inside a vein.

const CELL := 70.0               # m: one vein at most a cell
const NEAR := 220.0              # m: the veins known round you
const CHANCE := 0.4
const SEEN := 160.0              # m: the scanner shows those within this
const GHOST_TIME := 60.0         # s
const PER_CARVE := 4             # units a carve that cuts into it
const SENT := 16                 # the veins the terrain shader knows (the nearest; its VEINS)
const SENT_PTS := 384            # their points (its vein_pts: each vein its chains one after another, a break (radius -1) between)
const FADE := 6.0                # s: the ghost fading out at its end
const HOLO_SIDES := 10           # the hologram tube's sides
const HOLO_SUB := 4              # its rings between two of a vein's points (a smooth curve through them)

var cosmos: Node
var planet: CosmosPlanet
var veins := {}                  # key -> {key, pts (planet-local), r, mineral, units, max}
var _at := Vector3(INF, INF, INF)
var _task := -1
var _found: Array = []
var _check := 0.0
var ghosted := {}                # key -> true: the veins the scanner's shown (till ghost_until)
var ghost_until := 0.0           # (s, ticks)
var ghost_k := 0.0               # the ghost's strength now (the shader's)
var _sent_mat: ShaderMaterial    # (the planet's terrain material the veins were sent to)
var _sent_at := Vector3(INF, INF, INF)
var _holo: MeshInstance3D        # (the scanned veins' hologram: a child of their world)
static var _holo_mats: Array = []   # [skin, wire] (shared)


func _ready() -> void:
	name = "Veins"


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _sent_mat and is_instance_valid(_sent_mat):
		_sent_mat.set_shader_parameter("vein_n", 0)
		_sent_mat.set_shader_parameter("ghost_k", 0.0)
	if is_instance_valid(_holo):
		_holo.queue_free()


func _pid() -> String:
	return str(planet.rec.get("id", planet.name)) if planet else ""


func _process(delta: float) -> void:
	var w: Node3D = cosmos.walker if cosmos else null
	var pl: CosmosPlanet = w.get("planet") if w else null
	if pl != planet:   # (another world, or none: its veins forgotten)
		planet = pl
		veins = {}
		_at = Vector3(INF, INF, INF)
		_clear_ghosts()
		_send(Vector3.ZERO)
	if planet == null or w.get("deck") != null:
		return
	var local: Vector3 = w.global_position - planet.global_position
	if not ghosted.is_empty():   # (the ghost: on for its minute, fading out at the end)
		var now := Time.get_ticks_msec() / 1000.0
		var k := clampf((ghost_until - now) / FADE, 0.0, 1.0)
		if k <= 0.0:
			_clear_ghosts()
			_send(local)
		elif absf(k - ghost_k) > 0.004:
			ghost_k = k
			for m: ShaderMaterial in holo_mats():
				m.set_shader_parameter("k", k)
	if local.distance_to(_sent_at) > 25.0:
		_send(local)   # (walked on: the nearest veins again)
	_check -= delta
	if _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_place(_found, local)
		_send(local)
	elif _task == -1 and _check <= 0.0 and local.distance_to(_at) > 30.0:
		_check = 0.5
		_at = local
		var dug: Dictionary = CosmosGame.extra.get("veins", {}).get(_pid(), {})
		var out := []
		_found = out
		var shape: PlanetShape = planet.shape
		var r: float = planet.radius
		var sd := int(shape.look.get("seed", 0.0) * 1000.0) + 7
		var mix: Dictionary = CosmosDeposits.MIX.get(str(planet.rec.get("type", "")), CosmosDeposits.MIX[""])
		var dd := dug.duplicate()
		_task = WorkerThreadPool.add_task(func(): out.append_array(_find(shape, r, sd, mix, local, dd)), true, "veins")


## (Worker) The veins within NEAR of `local`: [key, points, radius, mineral, units, max].
static func _find(shape: PlanetShape, radius: float, sd: int, mix: Dictionary, local: Vector3, dug: Dictionary) -> Array:
	var out := []
	if shape.kind != "rocky":
		return out
	var c0 := (local / CELL).floor()
	var n := int(ceil(NEAR / CELL))
	var total := 0.0
	for m in mix:
		total += float(mix[m])
	for x in range(-n, n + 1):
		for y in range(-n, n + 1):
			for z in range(-n, n + 1):
				var cell := c0 + Vector3(x, y, z)
				var cc := (cell + Vector3(0.5, 0.5, 0.5)) * CELL
				if absf(cc.length() - radius) > CELL * 1.5 or cc.distance_to(local) > NEAR + CELL:
					continue
				var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
				var left := float(dug.get(key, 1.0))   # (a mined-out one still there: its ore gone, its walls seen)
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([sd, key, "vein"])
				if rng.randf() > CHANCE:
					continue
				var d := ((cell + Vector3(rng.randf(), rng.randf(), rng.randf())) * CELL).normalized()
				var h := shape.height(d)
				if (shape.sea > 0 and h < 1.0) or shape.cleared(d):
					continue
				var start := d * (radius + h - rng.randf_range(3.0, 10.0))
				if (start / CELL).floor() != cell:
					continue
				var pick := rng.randf() * total
				var mineral: String = mix.keys()[0]
				for mm in mix:
					pick -= float(mix[mm])
					if pick <= 0.0:
						mineral = mm
						break
				var body := _shape(rng, start, shape, radius)
				var pts: Array = []
				for q: Vector4 in body[0][0]:
					pts.append(Vector3(q.x, q.y, q.z))
				var units := roundi(float(body[1]) * rng.randf_range(4.0, 7.0) + 40.0)
				out.append([key, pts, rng.randf_range(0.9, 1.7), mineral, maxi(1, roundi(units * left)) if left > 0.0 else 0, units, body])
	return out


## (Worker) A vein's body from `start`: a ragged, lumpy main lode wandering under the
## ground (swelling and pinching), and tendrils branching off it - thinning to nothing,
## kinking as they go, now and then forking again. Each chain [Vector4(point, radius)...]
## (planet-local); kept a little under the ground. [chains (the main one first), their length (m)].
static func _shape(rng: RandomNumberGenerator, start: Vector3, shape: PlanetShape, radius: float) -> Array:
	var under := func(p: Vector3, dmin: float, dmax: float) -> Vector3:
		var u := p.normalized()
		var top := radius + shape.height(u)
		return u * (top - clampf(top - p.length(), dmin, dmax))
	var d := start.normalized()
	var e := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized().rotated(d, rng.randf() * TAU)
	var base := rng.randf_range(0.8, 1.5)
	var main: Array = [Vector4(start.x, start.y, start.z, base * rng.randf_range(0.6, 1.0))]
	var p := start
	var length := 0.0
	for k in rng.randi_range(3, 5):   # (its core: short, ragged - a lump, not a worm)
		e = e.rotated(p.normalized(), rng.randf_range(-1.5, 1.5))
		var step := rng.randf_range(1.5, 3.2)
		var q: Vector3 = under.call(p + e * step + p.normalized() * rng.randf_range(-1.6, 1.6), 2.2, 12.0)
		length += q.distance_to(p)
		p = q
		main.append(Vector4(p.x, p.y, p.z, base * rng.randf_range(0.5, 1.7)))   # (swelling and pinching)
	var tip: Vector4 = main[-1]
	main[-1] = Vector4(tip.x, tip.y, tip.z, base * 0.3)
	var chains: Array = [main]
	var todo: Array = []   # [from point, direction, radius, forks left]
	for t in rng.randi_range(3, 7):   # (tendrils, every way out of it)
		var at: Vector4 = main[rng.randi_range(0, main.size() - 1)]
		var o := Vector3(at.x, at.y, at.z)
		var dir := e.rotated(o.normalized(), rng.randf_range(-PI, PI))
		dir = (dir + o.normalized() * rng.randf_range(-0.6, 0.35)).normalized()   # (mostly down or level)
		todo.append([o, dir, at.w * rng.randf_range(0.35, 0.6), 2])
	while not todo.is_empty() and chains.size() < 15:
		var tb: Array = todo.pop_back()
		var q: Vector3 = tb[0]
		var dir: Vector3 = tb[1]
		var r0: float = tb[2]
		var n := rng.randi_range(4, 8) - (2 - int(tb[3]))   # (forks shorter)
		var ch: Array = [Vector4(q.x, q.y, q.z, r0)]
		for k in n:
			dir = (dir.rotated(q.normalized(), rng.randf_range(-0.9, 0.9)) + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))).normalized()
			var nq: Vector3 = under.call(q + dir * rng.randf_range(1.4, 3.2), 1.6, 15.0)
			length += nq.distance_to(q)
			q = nq
			var r := r0 * pow(1.0 - float(k + 1) / n, 0.8) + 0.04   # (thinning to a point)
			ch.append(Vector4(q.x, q.y, q.z, r))
			if int(tb[3]) > 0 and k >= 1 and k < n - 1 and rng.randf() < 0.3:   # (a fork)
				todo.append([q, dir.rotated(q.normalized(), rng.randf_range(0.6, 1.2) * (1.0 if rng.randf() < 0.5 else -1.0)), r * 0.8, int(tb[3]) - 1])
		chains.append(ch)
	return [chains, length]


## A vein's chains (Vector4 point + radius); an old record without them: its one chain, as thick all along.
static func chains_of(v: Dictionary) -> Array:
	if v.has("chains"):
		return v["chains"]
	var ch: Array = []
	for q: Vector3 in v["pts"]:
		ch.append(Vector4(q.x, q.y, q.z, float(v["r"])))
	return [ch]


func _place(found: Array, local: Vector3) -> void:
	var keep := {}
	for f in found:
		keep[f[0]] = true
		if not veins.has(f[0]):
			veins[f[0]] = {"key": f[0], "pts": f[1], "r": float(f[2]), "mineral": f[3], "units": int(f[4]), "max": int(f[5]), "chains": f[6][0]}
	for k in veins.keys():
		if not keep.has(k) and (veins[k]["pts"][0] as Vector3).distance_to(local) > NEAR + 60.0:
			veins.erase(k)


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## The vein a carve at planet-local `c` (radius `r`) cuts into, or {}.
func vein_at(c: Vector3, r: float) -> Dictionary:
	for k in veins:
		var v: Dictionary = veins[k]
		if int(v["units"]) <= 0:
			continue
		for ch: Array in chains_of(v):
			for i in ch.size() - 1:
				var a: Vector4 = ch[i]
				var b: Vector4 = ch[i + 1]
				if _seg_dist(c, Vector3(a.x, a.y, a.z), Vector3(b.x, b.y, b.z)) < maxf(a.w, b.w) + r:
					return v
	return {}


## A carve of the terrain digger at planet-local `c`: what it cuts out of a vein - into your pack. Units got.
func dig(c: Vector3, r: float) -> int:
	var v := vein_at(c, r)
	if v.is_empty():
		return 0
	var data: Node = CosmosGame.data
	var n := mini(mini(PER_CARVE, int(v["units"])), int(data.room_for(str(v["mineral"]))))
	if n <= 0:
		return -1   # (your pack's full)
	v["units"] = int(v["units"]) - n
	data.add_item(str(v["mineral"]), n)
	if ghosted.has(v["key"]):
		_send(_sent_at)   # (what's left of it: its ghost the dimmer)
	var all: Dictionary = CosmosGame.extra.get("veins", {})
	var mine: Dictionary = all.get(_pid(), {})
	mine[v["key"]] = snappedf(float(v["units"]) / maxf(1.0, float(v["max"])), 0.001)
	all[_pid()] = mine
	CosmosGame.extra["veins"] = all
	return n


static func name_of(v: Dictionary) -> String:
	return "%s vein" % Items.info(str(v["mineral"])).get("name", v["mineral"])


## The scanner's pulse: the veins within SEEN of `me` (global) shown through the
## ground as a ghost for a minute (the terrain shader's glow - see _send); the
## ones with ore left, their [planet-local point, label] for its marks.
func reveal(me: Vector3) -> Array:
	var out := []
	if planet == null:
		return out
	var local := me - planet.global_position
	_clear_ghosts()
	for k in veins:
		var v: Dictionary = veins[k]
		var pts: Array = v["pts"]
		if (pts[0] as Vector3).distance_to(local) > SEEN:
			continue
		ghosted[k] = true   # (mined out ones too: grey)
		if int(v["units"]) <= 0:
			continue
		var top: Vector3 = pts[0]
		var down := planet.radius + planet.shape.height(top.normalized()) - top.length()
		out.append([top, "%s (%d) - %d m down" % [name_of(v), int(v["units"]), roundi(down)]])
	if not ghosted.is_empty():
		ghost_until = Time.get_ticks_msec() / 1000.0 + GHOST_TIME
		ghost_k = 1.0
		_show_holo()
	_send(local)
	return out


## The scanned veins' hologram (one mesh, two surfaces: the skin and the cage), on their world.
func _show_holo() -> void:
	var list: Array = []
	for key in ghosted:
		var v: Dictionary = veins.get(key, {})
		if v.is_empty():
			continue
		var lk: Array = CosmosDeposits.LOOK.get(str(v["mineral"]), CosmosDeposits.LOOK["iron_ore"])
		var c: Color = lk[0]
		c.a = clampf(float(v["units"]) / maxf(1.0, float(v["max"])), 0.0, 1.0)
		if int(v["units"]) <= 0:
			c = Color(0.55, 0.58, 0.62, 0.0)   # (dug out: grey)
		list.append({"chains": chains_of(v), "col": c})
	if list.is_empty() or planet == null:
		return
	_holo = MeshInstance3D.new()
	_holo.name = "VeinHologram"
	_holo.mesh = holo_mesh(list)
	_holo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mats := holo_mats()
	_holo.set_surface_override_material(0, mats[0])
	_holo.set_surface_override_material(1, mats[1])
	for m: ShaderMaterial in mats:
		m.set_shader_parameter("k", 1.0)
		if planet.material and planet.material.get_shader_parameter("cut_n") != null:   # (what's been dug already: grey in it - and as you dig, CosmosPlanet._send_cuts)
			m.set_shader_parameter("cuts", planet.material.get_shader_parameter("cuts"))
			m.set_shader_parameter("cut_n", planet.material.get_shader_parameter("cut_n"))
	planet.add_child(_holo)


## The hologram's two materials: the glass skin, the wire cage (made once, shared; warmed at the title).
static func holo_mats() -> Array:
	if _holo_mats.is_empty():
		var sh: Shader = load("res://shaders/world/vein_holo.gdshader")
		for w in [0.0, 1.0]:
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("wire", w)
			m.set_shader_parameter("cut_n", 0)
			m.render_priority = 2
			_holo_mats.append(m)
	return _holo_mats


## One chain of a vein (Vector4 point + radius) into the hologram's arrays: a smooth
## curve through its points (HOLO_SUB rings between two), its radius eased between them.
static func _holo_chain(ch: Array, col: Color, sv: PackedVector3Array, sn: PackedVector3Array, sc: PackedColorArray,
		si: PackedInt32Array, lv: PackedVector3Array, lc: PackedColorArray) -> void:
	if ch.size() < 2:
		return
	var ps: Array = []
	for q: Vector4 in ch:
		ps.append(Vector3(q.x, q.y, q.z))
	var path: Array = []   # [point, is one of the vein's own points, radius]
	for i in ps.size() - 1:
		var p0: Vector3 = ps[maxi(i - 1, 0)]
		var p1: Vector3 = ps[i]
		var p2: Vector3 = ps[i + 1]
		var p3: Vector3 = ps[mini(i + 2, ps.size() - 1)]
		for j in HOLO_SUB:
			var t := float(j) / HOLO_SUB
			var t2 := t * t
			var t3 := t2 * t
			path.append([0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3), j == 0,
				lerpf((ch[i] as Vector4).w, (ch[i + 1] as Vector4).w, smoothstep(0.0, 1.0, t))])
	path.append([ps[-1], true, (ch[-1] as Vector4).w])
	var n := path.size()
	var side := Vector3.ZERO   # (carried along the curve: the rings don't twist)
	var base := sv.size()
	var rings: Array = []
	for i in n:
		var p: Vector3 = path[i][0]
		var tan: Vector3 = ((path[mini(i + 1, n - 1)][0] as Vector3) - (path[maxi(i - 1, 0)][0] as Vector3)).normalized()
		if side == Vector3.ZERO:
			side = tan.cross(p.normalized())
			if side.length() < 0.1:
				side = tan.cross(Vector3.RIGHT)
		side = (side - tan * side.dot(tan)).normalized()
		var up := tan.cross(side)
		var rr: float = path[i][2]
		var ring := PackedVector3Array()
		for s in HOLO_SIDES:
			var a := TAU * s / HOLO_SIDES
			var dir := side * cos(a) + up * sin(a)
			var q := p + dir * rr
			sv.append(q)
			sn.append(dir)
			sc.append(col)
			ring.append(q)
		rings.append(ring)
		if bool(path[i][1]) or i == 0 or i == n - 1:   # (the cage's rings: at the vein's own points)
			for s in HOLO_SIDES:
				lv.append(ring[s])
				lv.append(ring[(s + 1) % HOLO_SIDES])
				lc.append(col)
				lc.append(col)
	for i in n - 1:
		for s in HOLO_SIDES:
			var a0 := base + i * HOLO_SIDES + s
			var a1 := base + i * HOLO_SIDES + (s + 1) % HOLO_SIDES
			var b0 := a0 + HOLO_SIDES
			var b1 := a1 + HOLO_SIDES
			si.append_array([a0, b0, a1, a1, b0, b1])
			lv.append((rings[i] as PackedVector3Array)[s])   # (the cage's lines along it)
			lv.append((rings[i + 1] as PackedVector3Array)[s])
			lc.append(col)
			lc.append(col)


## Veins as a hologram mesh: each [{chains (Vector4 point + radius) - or pts and r - , col}] its chains as
## tubes along smooth curves through their points (_holo_chain), HOLO_SIDES round, as thick as its
## ore there - surface 0 its skin (triangles), surface 1 its cage (lines: a ring at each of
## its points, and HOLO_SIDES lines along it). Vertex colour: its ore's, alpha what's left.
static func holo_mesh(list: Array) -> ArrayMesh:
	var sv := PackedVector3Array()
	var sn := PackedVector3Array()
	var sc := PackedColorArray()
	var si := PackedInt32Array()
	var lv := PackedVector3Array()
	var lc := PackedColorArray()
	for v: Dictionary in list:
		var col: Color = v["col"]
		for ch: Array in chains_of(v):
			_holo_chain(ch, col, sv, sn, sc, si, lv, lc)
	var mesh := ArrayMesh.new()
	if si.is_empty():
		return mesh
	var skin := []
	skin.resize(Mesh.ARRAY_MAX)
	skin[Mesh.ARRAY_VERTEX] = sv
	skin[Mesh.ARRAY_NORMAL] = sn
	skin[Mesh.ARRAY_COLOR] = sc
	skin[Mesh.ARRAY_INDEX] = si
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, skin)
	var cage := []
	cage.resize(Mesh.ARRAY_MAX)
	cage[Mesh.ARRAY_VERTEX] = lv
	cage[Mesh.ARRAY_COLOR] = lc
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, cage)
	return mesh


## The veins shown by the scanner now.
func ghosts() -> int:
	return ghosted.size() if ghost_k > 0.0 else 0


func _clear_ghosts() -> void:
	ghosted = {}
	ghost_k = 0.0
	if is_instance_valid(_holo):
		_holo.queue_free()
	_holo = null


## The veins round `local` (planet-local) to the planet's terrain shader: the
## shown ones first, then the nearest - their chains (points, radius), colour
## (LOOK's), what's left, metal / glow / crystal; how many are ghosted (the
## first ones), the ghost's strength. Up to SENT of them (SENT_PTS points);
## none on other worlds.
func _send(local: Vector3) -> void:
	var mat: ShaderMaterial = planet.material if planet and planet.shape.kind == "rocky" else null
	if _sent_mat and _sent_mat != mat and is_instance_valid(_sent_mat):
		_sent_mat.set_shader_parameter("vein_n", 0)
		_sent_mat.set_shader_parameter("ghost_k", 0.0)
	_sent_mat = mat
	_sent_at = local
	if mat == null:
		return
	var list: Array = veins.values()
	list.sort_custom(func(a, b):
		var ga := ghosted.has(a["key"])
		if ga != ghosted.has(b["key"]):
			return ga
		return (a["pts"][0] as Vector3).distance_squared_to(local) < (b["pts"][0] as Vector3).distance_squared_to(local))
	var bound := PackedVector4Array()
	var col := PackedVector4Array()
	var look := PackedVector4Array()
	var span := PackedVector4Array()
	var pts := PackedVector4Array()
	var shown := 0
	for v: Dictionary in list:
		var flat: Array = []   # (its chains one after another, a break between: no segment joins them)
		for ch: Array in chains_of(v):
			if not flat.is_empty():
				flat.append(Vector4(0.0, 0.0, 0.0, -1.0))
			flat.append_array(ch)
		if bound.size() >= SENT or pts.size() + flat.size() > SENT_PTS:
			break
		var r := 0.0
		var mid := Vector3.ZERO
		var m := 0
		for q: Vector4 in flat:
			if q.w >= 0.0:
				mid += Vector3(q.x, q.y, q.z)
				r = maxf(r, q.w)
				m += 1
		mid /= maxi(m, 1)
		var reach := 0.0
		for q: Vector4 in flat:
			if q.w >= 0.0:
				reach = maxf(reach, mid.distance_to(Vector3(q.x, q.y, q.z)))
		var lk: Array = CosmosDeposits.LOOK.get(str(v["mineral"]), CosmosDeposits.LOOK["iron_ore"])
		var c: Color = lk[0]
		span.append(Vector4(pts.size(), pts.size() + flat.size(), 0.0, 0.0))
		pts.append_array(flat)
		bound.append(Vector4(mid.x, mid.y, mid.z, reach + r * 2.7 + 0.5))   # (its ghost's halo across the ground; its ore's reach)
		col.append(Vector4(c.r, c.g, c.b, clampf(float(v["units"]) / maxf(1.0, float(v["max"])), 0.0, 1.0)))
		look.append(Vector4(float(lk[1]), float(lk[2]), 1.0 if lk[3] else 0.0, 0.0))
		if ghosted.has(v["key"]):
			shown += 1   # (they come first: the shader's ghost_n)
	var n := bound.size()
	bound.resize(SENT)
	col.resize(SENT)
	look.resize(SENT)
	span.resize(SENT)
	pts.resize(SENT_PTS)
	mat.set_shader_parameter("vein_bound", bound)
	mat.set_shader_parameter("vein_col", col)
	mat.set_shader_parameter("vein_look", look)
	mat.set_shader_parameter("vein_span", span)
	mat.set_shader_parameter("vein_pts", pts)
	mat.set_shader_parameter("vein_n", n)
	mat.set_shader_parameter("ghost_n", 0)   # (no glow over the ground: the scanned ones are holograms now)
	mat.set_shader_parameter("ghost_k", 0.0)
