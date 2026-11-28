class_name CosmosDeposits
extends Node3D
## Mineral deposits on a planet's ground and mining them on foot (Cosmos): round
## you as you walk, outcrops of the planet's minerals stand on the ground -
## crystal clusters (ice, salt, sulphur, obsidian, orichalcum) and boulders
## veined with ore (iron, copper, tin, silver, gold, cobalt, titanium,
## platinum) - which minerals by the kind of world (MIX). Each from its own
## cell of a grid over the planet (seeded: the same ones in the same places
## every visit), found on a worker as you move.
##
## Fire with your sights on one within RANGE and your mining beam cuts it
## instead of the rifle: ore comes off into your pack (the mineral itself),
## the deposit shrinks and at the last unit breaks up and is gone - for good
## (CosmosGame.extra "dug"). The beam heats as it cuts (harder minerals
## faster); at the top it overheats and stops until it's cooled right down.
##
## The terrain digger (V switches the rifle for it): fire and the beam carves
## the ground where your sights are - a sphere out of it each DIG_EVERY s
## (PlanetShape.dig; drawn by the planet's voxels - CosmosPlanet.redig): held
## on one spot it bores in along the beam, swept it cuts a trench; tunnels,
## overhangs. Plants and boulders in it go. Not in a town. It heats the beam too.
## Each carve cuts a block of building stone loose, a tree it fells its timber
## (the builder's materials - CosmosBuilds).

const CELL := 40.0              # m: one deposit at most a cell
const NEAR := 130.0             # m: the deposits kept round you
const MOVE := 18.0              # m: walked this far, the set's looked over again
const CHANCE := 0.55            # a cell's chance of one (its point must land in it too)
const RANGE := 30.0             # m: the beam's reach
const RATE := 3.0               # units a second
const HEAT := 0.22              # a second, at hardness 1
const COOL := 0.35
const UNITS_PER_M := 14.0       # units a metre of size
const DIG_R := 2.0              # m: a carve's sphere (held on one spot, each goes 0.4 of it further in)
const DIG_EVERY := 0.15         # s
const DIG_MOST := 30.0          # m: the deepest under the ground a carve goes
const DIG_HEAT := 0.13          # a second

## The kinds of world -> {mineral: weight}.
const MIX := {
	"glacier": {"ice": 4, "salt": 2.5, "silver_ore": 2, "cobalt": 1.5},
	"inferno": {"sulphur": 3.5, "obsidian": 3, "iron_ore": 2, "gold_ore": 1.5},
	"ocean": {"copper_ore": 3, "salt": 2.5, "iron_ore": 2.5, "tin_ore": 2},
	"alien": {"copper_ore": 2.5, "iron_ore": 2.5, "silver_ore": 2, "tin_ore": 1.5, "orichalcum": 0.8},
	"barren": {"iron_ore": 3.5, "titanium_ore": 3, "cobalt": 2, "platinum_ore": 1.5},
	"moon": {"iron_ore": 3, "titanium_ore": 3, "platinum_ore": 1.5, "ice": 1.5},
	"": {"iron_ore": 4, "copper_ore": 3, "tin_ore": 3},
}
## A mineral's look: tint, metallic, glow, crystal (else an ore boulder).
const LOOK := {
	"ice": [Color(0.72, 0.88, 1.0), 0.0, 0.08, true], "salt": [Color(0.93, 0.9, 0.85), 0.0, 0.0, true],
	"sulphur": [Color(0.95, 0.82, 0.18), 0.0, 0.05, true], "obsidian": [Color(0.07, 0.065, 0.09), 0.2, 0.0, true],
	"orichalcum": [Color(1.0, 0.52, 0.22), 0.9, 0.25, true],
	"iron_ore": [Color(0.55, 0.27, 0.16), 0.6, 0.0, false], "copper_ore": [Color(0.3, 0.62, 0.5), 0.4, 0.0, false],
	"tin_ore": [Color(0.72, 0.73, 0.72), 0.9, 0.0, false], "silver_ore": [Color(0.86, 0.87, 0.9), 1.0, 0.0, false],
	"gold_ore": [Color(1.0, 0.76, 0.3), 1.0, 0.03, false], "cobalt": [Color(0.22, 0.34, 0.85), 0.7, 0.04, false],
	"titanium_ore": [Color(0.62, 0.64, 0.68), 0.9, 0.0, false], "platinum_ore": [Color(0.86, 0.85, 0.8), 1.0, 0.0, false],
}

static var _meshes: Array = []   # [crystal cluster, ore boulder]
static var _mat: ShaderMaterial
static var _beam_mat: StandardMaterial3D

var cosmos: Node
var planet: CosmosPlanet
var deps := {}                  # cell key -> {key, node, at (planet-local), up, size, mineral, units, max}
var focus: Dictionary = {}      # the deposit under the sights (in reach), or {}
var heat := 0.0                 # the beam's: 0 .. 1
var overheated := false
var active := false             # the beam on (this frame)
var got := {}                   # mineral -> units cut (this walk; the HUD's)
var _acc := 0.0
var _at := Vector3(INF, INF, INF)   # (planet-local: where the set was last looked over)
var _task := -1
var _found: Array = []
var _beam: MeshInstance3D
var _flare: MeshInstance3D
var _t := 0.0
var _check := 0.0
var digger := false             # the terrain digger out (else the rifle)
var dig_at := Vector3.ZERO      # (where it cuts, global; ZERO: nowhere in reach)
var digs := 0                   # (cuts made: tests, the HUD)
var _dig_t := 0.0


## The shared meshes: a crystal cluster (hexagonal prisms with pointed tips,
## leaning out of a stub of rock) and an ore boulder (a lumpy sphere), unit
## sized, the crystal parts marked in the vertex colour (red = 1).
static func meshes() -> Array:
	if not _meshes.is_empty():
		return _meshes
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	_lump(st, Vector3(0, 0.1, 0), Vector3(0.75, 0.35, 0.7), 11, 0.0)
	for k in 9:
		var lean := Vector3(rng.randf_range(-0.55, 0.55), 1.0, rng.randf_range(-0.55, 0.55)).normalized()
		if k == 0:
			lean = Vector3(0.05, 1, 0.08).normalized()
		var base := Vector3(rng.randf_range(-0.4, 0.4), 0.15, rng.randf_range(-0.4, 0.4)) * (0.3 if k == 0 else 1.0)
		var len := rng.randf_range(0.5, 0.95) * (1.6 if k == 0 else 1.0)
		_prism(st, base, lean, len, rng.randf_range(0.09, 0.16) * (1.5 if k == 0 else 1.0), rng.randf() * TAU)
	st.generate_normals()
	_meshes.append(LodKit.commit(st))   # (with its levels of detail - LodKit)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lump(st, Vector3(0, 0.38, 0), Vector3(0.75, 0.5, 0.65), 77, 0.0)
	_lump(st, Vector3(0.45, 0.2, 0.25), Vector3(0.35, 0.28, 0.32), 78, 0.0)
	st.generate_normals()
	_meshes.append(LodKit.commit(st))   # (with its levels of detail - LodKit)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/world/deposit.gdshader")
	return _meshes


## A hexagonal crystal: six sides from `base` along `dir`, `len` long, a point on top.
static func _prism(st: SurfaceTool, base: Vector3, dir: Vector3, len: float, r: float, turn: float) -> void:
	var x := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized().rotated(dir, turn)
	var z := dir.cross(x)
	var top := base + dir * len
	var tip := top + dir * r * 2.2
	st.set_color(Color(1, 0, 0))
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		var o0 := (x * cos(a0) + z * sin(a0)) * r
		var o1 := (x * cos(a1) + z * sin(a1)) * r
		for v in [base + o0, top + o0, top + o1, base + o0, top + o1, base + o1, top + o0, tip, top + o1]:
			st.add_vertex(v)


## A lump of rock: a sphere pushed about by noise, at `c` with radii `s`.
static func _lump(st: SurfaceTool, c: Vector3, s: Vector3, seed: int, crystal: float) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 1.1
	var segs := 14
	var rings := 8
	st.set_color(Color(crystal, 0, 0))
	var pt := func(r: int, g: int) -> Vector3:
		var th := PI * r / rings
		var ph := TAU * g / segs
		var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
		return c + d * (1.0 + n.get_noise_3dv(d * 1.4) * 0.35) * s
	for r in rings:
		for g in segs:
			var a: Vector3 = pt.call(r, g)
			var b: Vector3 = pt.call(r, g + 1)
			var cc: Vector3 = pt.call(r + 1, g)
			var d: Vector3 = pt.call(r + 1, g + 1)
			for v in [a, cc, b, b, cc, d]:   # (clockwise seen from outside: Godot's front faces - not the lump's insides)
				st.add_vertex(v)


func _ready() -> void:
	name = "Deposits"
	meshes()
	if cosmos and cosmos.get("noise"):
		_mat.set_shader_parameter("noise_tex", cosmos.noise)
	if _beam_mat == null:   # (one for the run: its shader not made again each system)
		_beam_mat = StandardMaterial3D.new()
		_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_beam_mat.albedo_color = Color(0.55, 1.0, 1.0, 1.0)
	var bm := _beam_mat
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.085
	cyl.bottom_radius = 0.085
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	_beam.mesh = cyl
	_beam.material_override = bm
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	_flare = MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.25
	sp.height = 0.5
	sp.radial_segments = 8
	sp.rings = 4
	_flare.mesh = sp
	_flare.material_override = bm
	_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flare.visible = false
	add_child(_flare)


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _process(delta: float) -> void:
	_t += delta
	var w: Node3D = cosmos.walker if cosmos and is_instance_valid(cosmos.walker) else null   # (freed already: leaving the game)
	if w == null or planet == null or w.get("planet") != planet:
		return
	# The set round you: looked over on a worker when you've moved (paced by time).
	_check -= delta
	var local: Vector3 = planet.to_local(w.global_position)
	if _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_place(_found, local)
	elif _task == -1 and _check <= 0.0 and local.distance_to(_at) > MOVE:
		_check = 0.4
		_at = local
		var dug: Dictionary = CosmosGame.extra.get("dug", {}).get(_pid(), {})
		var out := []
		_found = out
		var shape: PlanetShape = planet.shape
		var r: float = planet.radius
		var sd := int(shape.look.get("seed", 0.0) * 1000.0)
		var mix: Dictionary = MIX.get(str(planet.rec.get("type", "")), MIX[""])
		_task = WorkerThreadPool.add_task(func(): out.append_array(_find(shape, r, sd, mix, local, dug.duplicate())), true, "deposits")


func _pid() -> String:
	return str(planet.rec.get("id", planet.name))


## (Worker) The deposits within NEAR of `local`: [key, at, up, size, mineral, units left share].
static func _find(shape: PlanetShape, radius: float, sd: int, mix: Dictionary, local: Vector3, dug: Dictionary) -> Array:
	var out := []
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
				if absf(cc.length() - radius) > CELL * 1.8 or cc.distance_to(local) > NEAR + CELL:
					continue
				var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
				var left := float(dug.get(key, 1.0))
				if left <= 0.0:
					continue
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([sd, key])
				if rng.randf() > CHANCE:
					continue
				var d := ((cell + Vector3(rng.randf(), rng.randf(), rng.randf())) * CELL).normalized()
				var h := shape.height(d)
				var at := d * (radius + h)
				if (at / CELL).floor() != cell or at.distance_to(local) > NEAR:
					continue   # (its ground in another cell: that cell's)
				if (shape.sea > 0 and h < 0.4) or shape.cleared(d):
					continue
				var pick := rng.randf() * total
				var mineral: String = mix.keys()[0]
				for mm in mix:
					pick -= float(mix[mm])
					if pick <= 0.0:
						mineral = mm
						break
				var size := rng.randf_range(0.9, 2.2) * (1.4 if rng.randf() < 0.15 else 1.0)
				out.append([key, at, d, size, mineral, left, rng.randf() * TAU])
	return out


## The set found: new ones made, the far ones dropped.
func _place(found: Array, local: Vector3) -> void:
	var keep := {}
	for f in found:
		keep[f[0]] = true
		if deps.has(f[0]):
			continue
		var look: Array = LOOK.get(f[4], LOOK["iron_ore"])
		var mi := MeshInstance3D.new()
		mi.mesh = _meshes[0 if look[3] else 1]
		mi.material_override = _mat
		mi.visibility_range_end = 110.0   # (beyond, a deposit's a speck: not drawn)
		add_child(mi)
		mi.set_instance_shader_parameter("tint", look[0])
		mi.set_instance_shader_parameter("metal", look[1])
		mi.set_instance_shader_parameter("glow", look[2])
		var up: Vector3 = f[2]
		var x := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized().rotated(up, float(f[6]))
		var units := int(float(f[3]) * UNITS_PER_M)
		var dep := {"key": f[0], "node": mi, "at": f[1], "up": up, "size": float(f[3]), "basis": Basis(x, up, x.cross(up)),
			"mineral": f[4], "max": units, "units": maxi(1, int(units * float(f[5])))}
		deps[f[0]] = dep
		_shape_of(dep)
	for k in deps.keys():
		if not keep.has(k) and (deps[k]["at"] as Vector3).distance_to(local) > NEAR + 30.0:
			(deps[k]["node"] as Node).queue_free()
			deps.erase(k)


## A deposit's size by what's left of it (planet-local; this node rides the planet).
func _shape_of(dep: Dictionary) -> void:
	var left := float(dep["units"]) / maxf(1.0, float(dep["max"]))
	var s := float(dep["size"]) * (0.3 + 0.7 * sqrt(left))
	(dep["node"] as Node3D).transform = Transform3D((dep["basis"] as Basis).scaled(Vector3.ONE * s), (dep["at"] as Vector3) - (dep["up"] as Vector3) * 0.12 * s)


## Its middle and radius (global): what the sights and your feet meet.
func _sphere(dep: Dictionary) -> Array:
	var left := float(dep["units"]) / maxf(1.0, float(dep["max"]))
	var s := float(dep["size"]) * (0.3 + 0.7 * sqrt(left))
	return [planet.to_global((dep["at"] as Vector3) + (dep["up"] as Vector3) * s * 0.45), s * 0.7]


## The deposit a line from `o` along `dir` meets first within `reach`: [dep, distance] or [].
func under(o: Vector3, dir: Vector3, reach: float) -> Array:
	var best: Array = []
	var bt := reach
	for k in deps:
		var sp := _sphere(deps[k])
		var oc: Vector3 = o - sp[0]
		var b := oc.dot(dir)
		var disc := b * b - (oc.dot(oc) - float(sp[1]) * float(sp[1]))
		if disc < 0.0:
			continue
		var t := -b - sqrt(disc)
		if t > 0.0 and t < bt:
			bt = t
			best = [deps[k], t]
	return best


## The walker kept out of the deposits (their middles: you step round them).
func push(w: Node3D) -> void:
	var u: Vector3 = w.up()
	for k in deps:
		var sp := _sphere(deps[k])
		var d: Vector3 = w.global_position - sp[0]
		var flat := d - u * d.dot(u)
		var need := float(sp[1]) * 0.8 + CosmosWalker.BODY_R
		if flat.length() < need and flat.length() > 0.001 and d.dot(u) < float(sp[1]):
			w.global_position += flat.normalized() * (need - flat.length())


## Every frame on foot: the beam, if you're firing at a deposit in reach -
## true while it mines (the rifle holds its fire).
func step(delta: float, firing: bool) -> bool:
	active = false
	if not overheated:
		heat = maxf(0.0, heat - COOL * delta * (0.0 if firing else 1.0))
	else:
		heat = maxf(0.0, heat - COOL * 1.4 * delta)
		if heat <= 0.0:
			overheated = false
	var cam: Camera3D = cosmos.cam
	var w: Node3D = cosmos.walker
	focus = {}
	var h := under(cam.global_position, -cam.global_basis.z, RANGE + cam.global_position.distance_to(w.global_position))
	if not h.is_empty() and (_sphere(h[0])[0] as Vector3).distance_to(w.global_position) < RANGE + float(_sphere(h[0])[1]):
		focus = h[0]
	if focus.is_empty() and digger:
		return _dig(delta, firing)
	if not firing or focus.is_empty():
		_show(false, Vector3.ZERO)
		return false
	if overheated:
		_show(false, Vector3.ZERO)
		return true   # (the trigger held on the deposit: no rifle shot into it)
	var hit: Vector3 = cam.global_position - cam.global_basis.z * float(h[1])
	var mineral: String = focus["mineral"]
	var data: Node = CosmosGame.data
	if data.room_for(mineral) <= 0:
		_say("Your pack is full")
		_show(false, Vector3.ZERO)
		return true
	var hard := float(Mining.MINERALS.get(mineral, {"hard": 1.0})["hard"])
	heat += HEAT * hard * delta
	if heat >= 1.0:
		heat = 1.0
		overheated = true
		_say("Mining beam overheated - let it cool")
	_acc += RATE * delta
	while _acc >= 1.0 and int(focus["units"]) > 0:
		_acc -= 1.0
		focus["units"] = int(focus["units"]) - 1
		data.add_item(mineral, 1)
		got[mineral] = int(got.get(mineral, 0)) + 1
	_shape_of(focus)
	_save(focus)
	if int(focus["units"]) <= 0:
		cosmos.hud.flash("%s deposit mined out - %d %s" % [_name(mineral), int(focus["max"]), _name(mineral)])
		(focus["node"] as Node).queue_free()
		deps.erase(focus["key"])
		focus = {}
		_show(false, Vector3.ZERO)
		return true
	(focus["node"] as GeometryInstance3D).set_instance_shader_parameter("heat", clampf(heat, 0.2, 1.0))
	_show(true, hit)
	return true


## The digger, firing: a sphere carved out of the ground where the sights
## meet it (its middle a little back along the beam: held on, it bores in
## along it - down, or into a hillside), each DIG_EVERY s. True whenever it's
## out and you fire (the rifle never shoots then).
func _dig(delta: float, firing: bool) -> bool:
	_dig_t -= delta
	if not firing or overheated:
		dig_at = Vector3.ZERO
		_show(false, Vector3.ZERO)
		return firing
	var cam: Camera3D = cosmos.cam
	var w: Node3D = cosmos.walker
	var dir := -cam.global_basis.z
	if _dig_t <= 0.0 or dig_at == Vector3.ZERO:
		_dig_t = DIG_EVERY
		dig_at = ground_hit(cam.global_position, dir, RANGE + cam.global_position.distance_to(w.global_position))
		if dig_at != Vector3.ZERO and dig_at.distance_to(w.global_position) < RANGE:
			var c := planet.to_local(dig_at - dir * DIG_R * 0.6)   # (planet-local)
			var d := c.normalized()
			var top := c.length() - planet.radius
			if cosmos.get("builds") and cosmos.builds.damage_at(dig_at, DIG_R * 0.75, 30.0):
				pass   # (its beam on something built: that worn, the ground left)
			elif planet.shape.cleared(d):
				_say("Not in a town")
				dig_at = Vector3.ZERO
			elif top > planet.shape.height(d) - DIG_MOST and planet.shape.dig(d, DIG_R, top) >= 0:
				digs += 1
				_quarry(c)   # (before the redig: the trees it fells still known)
				planet.redig(c, DIG_R)
				var vein: Node = cosmos.get("veins")
				if vein:   # (cut into a vein: its ore, far more of it than a deposit's)
					var n: int = vein.dig(c, DIG_R)
					if n > 0:
						var v: Dictionary = vein.vein_at(c, DIG_R + 0.5)
						var mineral := str(v.get("mineral", "")) if not v.is_empty() else ""
						if mineral != "":
							got[mineral] = int(got.get(mineral, 0)) + n
						_say("+%d %s - the vein: %d left" % [n, _name(mineral) if mineral != "" else "ore", int(v.get("units", 0))])
						if cosmos.has_method("note_event"):
							cosmos.note_event("vein_dug")
					elif n < 0:
						_say("Your pack is full")
		else:
			dig_at = Vector3.ZERO
	if dig_at == Vector3.ZERO:
		_show(false, Vector3.ZERO)
		return true
	heat += DIG_HEAT * delta
	if heat >= 1.0:
		heat = 1.0
		overheated = true
		_say("Mining beam overheated - let it cool")
	_show(true, dig_at)
	return true


## What a carve at planet-local `c` cuts loose for building: a block of
## stone (CosmosBuilds' stone tier) into your hold, and timber from a tree it
## fells (each tree once).
var _felled := {}


func _quarry(c: Vector3) -> void:
	var data: Node = CosmosGame.data
	if data.room_for("stone") > 0:
		data.add_item("stone", 1)
		got["stone"] = int(got.get("stone", 0)) + 1
	for rk in planet.rocks_near(c, DIG_R + 0.5):
		var r := float(rk[1])
		var h := float(rk[2])
		if h < r * 2.5:
			continue   # (a boulder, not a trunk)
		var at: Vector3 = rk[0]
		var k := "%d,%d,%d" % [roundi(at.x), roundi(at.y), roundi(at.z)]
		if _felled.has(k) or data.room_for("timber") <= 0:
			continue
		_felled[k] = true
		var n := clampi(roundi(h * 0.8), 3, 12)
		data.add_item("timber", n)
		got["timber"] = int(got.get("timber", 0)) + n
		_say("+%d timber - a tree felled" % n)


## Where a line from `o` along `dir` first meets the solid ground within
## `reach` (global; carves and all), or ZERO: steps of 0.6 m, then halved down to ~1 cm.
func ground_hit(o: Vector3, dir: Vector3, reach: float) -> Vector3:
	var shape: PlanetShape = planet.shape
	var inv := planet.global_transform.affine_inverse()   # (planet-local: its ground turns with it)
	var solid := func(t: float) -> bool:
		return shape.density(inv * (o + dir * t)) < 0.0
	var t0 := 0.0
	var t := 0.6
	while t <= reach:
		if solid.call(t):
			for k in 6:
				var mid := (t0 + t) * 0.5
				if solid.call(mid):
					t = mid
				else:
					t0 = mid
			return o + dir * t
		t0 = t
		t += 0.6
	return Vector3.ZERO


func toggle_digger() -> void:
	digger = not digger
	dig_at = Vector3.ZERO
	cosmos.hud.flash("Terrain digger" if digger else "Rifle")


func _save(dep: Dictionary) -> void:
	var all: Dictionary = CosmosGame.extra.get("dug", {})
	var mine: Dictionary = all.get(_pid(), {})
	mine[dep["key"]] = snappedf(float(dep["units"]) / maxf(1.0, float(dep["max"])), 0.001)
	all[_pid()] = mine
	CosmosGame.extra["dug"] = all


static func _name(mineral: String) -> String:
	return str(Items.ITEMS.get(mineral, {}).get("name", mineral.capitalize()))


## The label the HUD shows for the deposit under the sights.
func focus_text() -> String:
	if focus.is_empty():
		return ""
	return "%s deposit - %d left" % [_name(focus["mineral"]), int(focus["units"])]


var _said := -100000


func _say(text: String) -> void:
	if Time.get_ticks_msec() - _said > 4000:
		_said = Time.get_ticks_msec()
		cosmos.hud.flash(text)


## The beam: from the walker's hand to where it cuts, flickering; a flare there.
func _show(on: bool, hit: Vector3) -> void:
	active = on
	_beam.visible = on
	_flare.visible = on
	for k in deps:
		if deps[k] != focus or not on:
			(deps[k]["node"] as GeometryInstance3D).set_instance_shader_parameter("heat", 0.0)
	if not on:
		return
	var w: Node3D = cosmos.walker
	var u: Vector3 = w.up()
	var hand: Vector3 = w.global_position + u * 1.3 + w.facing * 0.6 + w.facing.cross(u) * -0.25
	var d := hit - hand
	var L := d.length()
	if L < 0.1:
		_beam.visible = false
		return
	var y := d / L
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var fl := 0.8 + 0.4 * sin(_t * 53.0) * sin(_t * 29.0)
	_beam.global_transform = Transform3D(Basis(x * fl, y * L, z * fl), hand + d * 0.5)
	_flare.global_transform = Transform3D(Basis().scaled(Vector3.ONE * (0.8 + 0.6 * fl)), hit)
