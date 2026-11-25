class_name Fx
extends Node3D
## Particle effects as data: data/effects.json (a mod overlays it - or a .merge of
## it - like any data file). Each effect is named and is a list of emitters
## (CPUParticles3D: simulated on the CPU, drawn as one MultiMesh each - the same on
## the desktop and in a browser, no particle shader to compile), plus a flash of
## light if it has one. An Fx node is one effect playing:
##   Fx.spawn("explosion", cosmos.world, at, 1.6)          a one-shot: gone (back in the pool) when done
##   var f := Fx.attach("mining_sparks", node); f.emitting = on     a looping one, on a thing
##
## Every live Fx rebuilds its emitters when its effect's definition changes
## (Fx.reload_all() - the file read again - or set_def() from the editors: Talos's
## Effects, the Live Editor's Particles tab), so edits show at once in the game.
##
## The effects' look: few materials, shared - fx_add.gdshader (glow, fire, spark,
## ring: added light), fx_smoke.gdshader (smoke, dust: lit, blended) and
## fx_debris.gdshader (lit solid pieces glowing with heat); CosmosWarm draws them
## once at the title. A particle's colour is its emitter's colour ramp times its
## emissive strength times the Fx's tint (set_tint: a landing's dust the ground's
## colour, a bolt's sparks its gun's).
##
## An emitter (PARAMS: every key, its default, range and meaning):
##   {name, material, mesh, amount, lifetime, one_shot, explosiveness, delay, shape,
##    size, direction, spread, velocity [min, max], gravity [x, y, z], damping [min, max],
##    scale [min, max], scale_curve [[t, k]...], colors [[t, "#rrggbbaa"]...], emissive...}
## An effect: {about, emitters: [...], light: {color, energy, range, life}, duration}.

const FILE := "res://data/effects.json"
## One-shots kept for reuse, per effect (finished ones wait hidden in their parent).
const POOL_MAX := 24
const MATERIALS := ["glow", "fire", "spark", "ring", "smoke", "debris"]
const MESHES := ["quad", "streak", "shard"]
const SHAPES := ["point", "sphere", "sphere_surface", "box", "ring"]
const ADD := preload("res://shaders/world/fx_add.gdshader")
const SMOKE := preload("res://shaders/world/fx_smoke.gdshader")
const DEBRIS := preload("res://shaders/world/fx_debris.gdshader")

## Every emitter key: [key, kind, default, min, max, label, help]
## (kinds: text, enum (min: the options), bool, int, float, range, vec3, colors, curve).
const PARAMS := [
	["name", "text", "emitter", null, null, "Name", "What this emitter is (for you: shown in the editors)."],
	["on", "bool", true, null, null, "On", "Off: the emitter isn't drawn (to look at the others alone)."],
	["material", "enum", "glow", MATERIALS, null, "Material", "glow: a soft light, added - fire: ragged flame burning away - spark: a streak along its flight\nring: a thin ring (a shockwave) - smoke: lit, blended billows (dust too) - debris: solid lit pieces, glowing with heat."],
	["mesh", "enum", "quad", MESHES, null, "Mesh", "What each particle is: a quad (glow, fire, smoke, ring), a streak (sparks) or a shard (debris)."],
	["billboard", "bool", true, null, null, "Billboard", "The quads face the camera. Off: they lie as the emitter turns them (a ring flat round the blast)."],
	["amount", "int", 16, 1, 512, "Amount", "How many particles (a one-shot: all of them; looping: alive at once)."],
	["lifetime", "float", 1.0, 0.02, 20.0, "Lifetime", "Seconds each particle lives."],
	["lifetime_random", "float", 0.0, 0.0, 1.0, "Lifetime random", "How much shorter some live (0: all the same, 1: anything down to none)."],
	["one_shot", "bool", true, null, null, "One-shot", "All its particles once (a burst). Off: it keeps emitting (a trail, a jet's dust)."],
	["explosiveness", "float", 1.0, 0.0, 1.0, "Explosiveness", "1: all at once. 0: spread evenly over the lifetime."],
	["delay", "float", 0.0, 0.0, 5.0, "Delay", "Seconds after the effect starts before this emitter does."],
	["shape", "enum", "point", SHAPES, null, "Shape", "Where particles start: a point, in a sphere, on a sphere's surface, in a box, on a ring (round the emitter's up)."],
	["size", "float", 0.0, 0.0, 50.0, "Shape size", "The shape's radius (the box: half its side), in metres."],
	["direction", "vec3", [0.0, 1.0, 0.0], -1.0, 1.0, "Direction", "Which way they fly (the emitter's own axes: up is its Y)."],
	["spread", "float", 180.0, 0.0, 180.0, "Spread", "Degrees round the direction (180: every way)."],
	["velocity", "range", [2.0, 6.0], 0.0, 500.0, "Velocity", "Starting speed, m/s (each particle: between the two)."],
	["gravity", "vec3", [0.0, 0.0, 0.0], -50.0, 50.0, "Gravity", "Acceleration, m/s2 (space: none; a planet: -9.8 down; smoke rising: up)."],
	["damping", "range", [0.0, 0.0], 0.0, 100.0, "Damping", "Slowing, m/s each second (air drag: sparks and smoke stop)."],
	["radial", "range", [0.0, 0.0], -100.0, 100.0, "Radial accel", "Pushed out from the centre (or pulled in, below 0), m/s2: dust rolling out from a landing."],
	["scale", "range", [1.0, 1.0], 0.0, 100.0, "Scale", "Each particle's size in metres (between the two)."],
	["scale_curve", "curve", [], 0.0, 4.0, "Scale over life", "The size through its life (x: age, y: times the scale). None: the same size all its life."],
	["angle", "range", [0.0, 360.0], -360.0, 360.0, "Angle", "Its starting turn, degrees (billboards: round the view; debris: its tumble)."],
	["spin", "range", [0.0, 0.0], -1440.0, 1440.0, "Spin", "Turning, degrees a second."],
	["colors", "colors", [[0.0, "#ffffffff"], [1.0, "#ffffff00"]], null, null, "Colour over life", "Its colour and opacity through its life (left: born, right: gone)."],
	["emissive", "float", 1.0, 0.0, 20.0, "Emissive", "How bright (the colours times this: over 1 glows past white)."],
	["tinted", "bool", true, null, null, "Takes the tint", "Coloured by the effect's tint where the game sets one (a bolt's colour, the ground's).\nOff: always its own colours (a bolt's dust stays dust-coloured)."],
	["align", "bool", false, null, null, "Align to flight", "Its Y along its velocity (sparks always are)."],
	["local", "bool", true, null, null, "Local space", "The particles move with the emitter (a blast with its ship). Off: they stay where they were let go (a trail)."],
]
const EFFECT_PARAMS := [
	["about", "text", "", null, null, "About", "What the effect is and where the game uses it."],
	["duration", "float", 1.0, 0.05, 30.0, "Duration", "A spawned effect's looping emitters stop after this many seconds."],
]
const LIGHT_PARAMS := [
	["color", "color", "#ffb060ff", null, null, "Light colour", "The flash of light's colour."],
	["energy", "float", 0.0, 0.0, 40.0, "Light energy", "How bright the flash (0: no light)."],
	["range", "float", 20.0, 0.5, 400.0, "Light range", "How far it reaches, m (times the effect's scale)."],
	["life", "float", 0.5, 0.02, 10.0, "Light life", "Seconds it takes to fade."],
]

static var defs := {}                 # name -> the effect's definition
static var order: Array = []          # names, as in the file
static var dirty := false             # changed since saved
static var _loaded := false
static var _mats := {}
static var _meshes := {}
static var _pool := {}                # name -> Array of idle Fx

var effect := ""
var attached := false
## A one-shot kept when done (not pooled, not freed: the editors' previews play it again).
var keep := false
var scale_k := 1.0
var tint := Color.WHITE
var playing := false
var emitting := true: set = set_emitting
var _t := 0.0
var _life := 1.0
var _light: OmniLight3D
var _emitters: Array = []             # CPUParticles3D, one per emitter of the definition
var _started: Array = []              # (delayed emitters: started yet)


# --- The data ----------------------------------------------------------------------

static func load_all() -> void:
	_loaded = true
	defs = {}
	order = []
	var et: GDScript = load("res://scripts/editor/edit_target.gd")
	var d = JSON.parse_string(FileAccess.get_file_as_string(et.read_path(FILE)))
	if d is Dictionary:
		for k in d:
			if str(k).begins_with("_") or not d[k] is Dictionary:
				continue
			defs[str(k)] = d[k]
			order.append(str(k))
	dirty = false


## The file read again (the game's, a mod's) and every live effect rebuilt.
static func reload_all() -> void:
	load_all()
	_refresh("")


static func names() -> Array:
	if not _loaded:
		load_all()
	return order.duplicate()


static func has(name: String) -> bool:
	if not _loaded:
		load_all()
	return defs.has(name)


## Effect `name`'s definition ({} - none).
static func def(name: String) -> Dictionary:
	if not _loaded:
		load_all()
	return defs.get(name, {})


## Changes an effect's definition: every live effect of it rebuilt at once.
static func set_def(name: String, d: Dictionary) -> void:
	if not _loaded:
		load_all()
	defs[name] = d
	if not order.has(name):
		order.append(name)
	dirty = true
	_refresh(name)


static func remove(name: String) -> void:
	defs.erase(name)
	order.erase(name)
	dirty = true
	_refresh(name)


static func rename(from: String, to: String) -> bool:
	if not defs.has(from) or defs.has(to) or to.strip_edges() == "":
		return false
	defs[to] = defs[from]
	defs.erase(from)
	order[order.find(from)] = to
	for n in _live():
		if n.effect == from:
			n.effect = to
	_pool.erase(from)
	dirty = true
	return true


## Every definition as it is now: {name: def} in order (to undo to, or to save).
static func snapshot() -> Dictionary:
	if not _loaded:
		load_all()
	var out := {}
	for k in order:
		out[k] = defs[k].duplicate(true)
	return out


## Puts back a snapshot (undo): the effects that differ rebuilt.
static func restore(s: Dictionary) -> void:
	var was := defs
	defs = {}
	order = []
	for k in s:
		defs[k] = (s[k] as Dictionary).duplicate(true)
		order.append(k)
	dirty = true
	for k in was:
		if not defs.has(k) or JSON.stringify(defs[k]) != JSON.stringify(was[k]):
			_refresh(k)
	for k in defs:
		if not was.has(k):
			_refresh(k)


## Writes data/effects.json through EditTarget (the game's file, or the mod being made).
static func save() -> bool:
	var et: GDScript = load("res://scripts/editor/edit_target.gd")
	if not et.writable():
		return false
	var f := FileAccess.open(et.write_path(FILE), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(snapshot(), "\t", false) + "\n")
	f.close()
	dirty = false
	return true


## A new emitter: every key at its default.
static func new_emitter() -> Dictionary:
	var e := {}
	for p in PARAMS:
		e[p[0]] = p[2].duplicate(true) if p[2] is Array else p[2]
	return e


## Emitter `e`'s value of `key` (its default when it hasn't one).
static func val(e: Dictionary, key: String) -> Variant:
	if e.has(key):
		return e[key]
	for p in PARAMS:
		if p[0] == key:
			return p[2]
	return null


static func param(key: String) -> Array:
	for p in PARAMS:
		if p[0] == key:
			return p
	return []


static func _rng2(v: Variant, d := Vector2.ZERO) -> Vector2:
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	if v is float or v is int:
		return Vector2(float(v), float(v))
	return d


static func _vec3(v: Variant, d := Vector3.ZERO) -> Vector3:
	if v is Array and v.size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return d


static func color_of(v: Variant, d := Color.WHITE) -> Color:
	if v is String:
		return Color.from_string(v, d)
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return d


static func gradient(stops: Variant) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	if stops is Array:
		var s: Array = stops.duplicate()
		s.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		for st in s:
			if st is Array and st.size() >= 2:
				offs.append(clampf(float(st[0]), 0.0, 1.0))
				cols.append(color_of(st[1]))
	if offs.is_empty():
		offs = PackedFloat32Array([0.0, 1.0])
		cols = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	g.offsets = offs
	g.colors = cols
	return g


static func curve(pts: Variant) -> Curve:
	if not pts is Array or (pts as Array).size() < 2:
		return null
	var c := Curve.new()
	var hi := 1.0
	for p in pts:
		hi = maxf(hi, float(p[1]))
	c.max_value = hi
	for p in pts:
		c.add_point(Vector2(clampf(float(p[0]), 0.0, 1.0), float(p[1])), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return c


# --- Playing -----------------------------------------------------------------------

## A one-shot effect at `global_pos` in `parent` (`scale` x its size, turned by `basis`:
## its Y the effect's up). Freed (pooled) when it's done. null: no such effect.
static func spawn(name: String, parent: Node, global_pos: Vector3, scale := 1.0, basis := Basis()) -> Fx:
	if parent == null or not is_instance_valid(parent) or not has(name):
		return null
	var fx := _take(name, parent)
	if fx == null:
		fx = Fx.new()
		fx.effect = name
		parent.add_child(fx)
	fx.scale_k = scale
	var b := Basis(basis.orthonormalized().get_rotation_quaternion()) if basis != Basis() else Basis()
	if fx.is_inside_tree():
		fx.global_transform = Transform3D(b.scaled(Vector3.ONE * scale), global_pos)
	else:
		fx.transform = Transform3D(b.scaled(Vector3.ONE * scale), global_pos)
	fx.play()
	return fx


## A looping effect on `parent` (at its origin; move it, or set `emitting`).
static func attach(name: String, parent: Node) -> Fx:
	if parent == null or not is_instance_valid(parent):
		return null
	var fx := Fx.new()
	fx.effect = name
	fx.attached = true
	fx.name = "Fx_" + name
	parent.add_child(fx)
	fx.play()
	return fx


## A basis whose Y is `up` (an effect's direction: a ground's normal, a hit's way back).
static func basis_up(up: Vector3) -> Basis:
	var y := up.normalized()
	if y.length_squared() < 0.5:
		return Basis()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


static func _take(name: String, parent: Node) -> Fx:
	var list: Array = _pool.get(name, [])
	while not list.is_empty():
		var fx = list.pop_back()
		if is_instance_valid(fx) and not fx.playing and fx.effect == name:
			if fx.get_parent() != parent:
				if fx.get_parent():
					fx.get_parent().remove_child(fx)
				parent.add_child(fx)
			return fx
	return null


## Every Fx node there is (in the tree).
static func _live() -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_nodes_in_group("fx") if tree else []


static func _refresh(name: String) -> void:
	for n in _live():
		if name == "" or n.effect == name:
			n.rebuild()


## The Fx nodes under `n` (itself included).
static func under(n: Node) -> Array:
	var out: Array = []
	if n == null:
		return out
	if n is Fx:
		out.append(n)
	for c in n.find_children("*", "Node3D", true, false):
		if c is Fx and (c as Fx).visible:
			out.append(c)
	return out


func _ready() -> void:
	add_to_group("fx")
	if _emitters.is_empty():
		rebuild()


func play() -> void:
	_t = 0.0
	playing = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	if _emitters.is_empty():
		rebuild()
	set_tint(Color.WHITE)
	_start_all()


func _start_all() -> void:
	var ems: Array = def(effect).get("emitters", [])
	for i in _emitters.size():
		var p: CPUParticles3D = _emitters[i]
		var e: Dictionary = ems[i] if i < ems.size() else {}
		var go: bool = bool(val(e, "on")) and (emitting or not attached)
		_started[i] = float(val(e, "delay")) <= 0.0
		if go and _started[i]:
			p.restart()
		else:
			p.emitting = false
	if _light:
		_light.visible = true


## On / off (a looping effect: its emitters; its one-shot emitters fire again on).
func set_emitting(on: bool) -> void:
	if emitting == on:
		return
	emitting = on
	if not is_inside_tree():
		return
	var ems: Array = def(effect).get("emitters", [])
	for i in _emitters.size():
		var p: CPUParticles3D = _emitters[i]
		var e: Dictionary = ems[i] if i < ems.size() else {}
		if on and bool(val(e, "on")):
			if p.one_shot:
				p.restart()
			else:
				p.emitting = true
		elif not on:
			p.emitting = false
	if on:
		_t = 0.0


## Its particles' colour times `c` (and the light's).
func set_tint(c: Color) -> void:
	tint = c
	var ems: Array = def(effect).get("emitters", [])
	for i in _emitters.size():
		var e: Dictionary = ems[i] if i < ems.size() else {}
		var k := float(val(e, "emissive"))
		var t := c if bool(val(e, "tinted")) else Color.WHITE
		(_emitters[i] as CPUParticles3D).color = Color(t.r * k, t.g * k, t.b * k, t.a)


## Its emitters made again from the definition (in place: the nodes kept when they can be).
func rebuild() -> void:
	var d := def(effect)
	var ems: Array = d.get("emitters", [])
	while _emitters.size() > ems.size():
		var p: CPUParticles3D = _emitters.pop_back()
		remove_child(p)
		p.queue_free()
	_started.resize(ems.size())
	_started.fill(false)
	_life = 0.05
	var dur := float(d.get("duration", 1.0))
	for i in ems.size():
		if i >= _emitters.size():
			var p := CPUParticles3D.new()
			p.name = "E%d" % i
			p.emitting = false
			add_child(p)
			_emitters.append(p)
		var e: Dictionary = ems[i] if ems[i] is Dictionary else {}
		configure(_emitters[i], e)
		var life := float(val(e, "lifetime"))
		var span := life * (2.0 - clampf(float(val(e, "explosiveness")), 0.0, 1.0)) if bool(val(e, "one_shot")) else dur + life
		_life = maxf(_life, float(val(e, "delay")) + span + 0.05)
	var l: Dictionary = d.get("light", {}) if d.get("light") is Dictionary else {}
	if float(l.get("energy", 0.0)) > 0.0:
		if _light == null:
			_light = OmniLight3D.new()
			_light.shadow_enabled = false
			_light.name = "Light"
			add_child(_light)
		_light.light_color = color_of(l.get("color", "#ffb060"))
		_life = maxf(_life, float(l.get("life", 0.5)))
	elif _light:
		_light.queue_free()
		_light = null
	set_tint(tint)
	if playing:
		_start_all()


## Emitter `e`'s values onto particles `p`.
static func configure(p: CPUParticles3D, e: Dictionary) -> void:
	var mat := str(val(e, "material"))
	p.visible = bool(val(e, "on"))
	p.amount = clampi(int(val(e, "amount")), 1, 4096)
	p.lifetime = maxf(0.02, float(val(e, "lifetime")))
	p.lifetime_randomness = clampf(float(val(e, "lifetime_random")), 0.0, 1.0)
	p.one_shot = bool(val(e, "one_shot"))
	p.explosiveness = clampf(float(val(e, "explosiveness")), 0.0, 1.0)
	p.local_coords = bool(val(e, "local"))
	p.draw_order = CPUParticles3D.DRAW_ORDER_INDEX
	var size := maxf(0.0, float(val(e, "size")))
	match str(val(e, "shape")):
		"sphere":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = maxf(size, 0.001)
		"sphere_surface":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
			p.emission_sphere_radius = maxf(size, 0.001)
		"box":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			p.emission_box_extents = Vector3.ONE * size
		"ring":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			p.emission_ring_axis = Vector3.UP
			p.emission_ring_radius = maxf(size, 0.001)
			p.emission_ring_inner_radius = size * 0.6
			p.emission_ring_height = 0.0
		_:
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	var dir := _vec3(val(e, "direction"), Vector3.UP)
	p.direction = dir if dir.length_squared() > 0.0001 else Vector3.UP
	p.spread = clampf(float(val(e, "spread")), 0.0, 180.0)
	p.flatness = 0.0
	p.gravity = _vec3(val(e, "gravity"))
	var v := _rng2(val(e, "velocity"))
	p.initial_velocity_min = v.x
	p.initial_velocity_max = maxf(v.x, v.y)
	var dm := _rng2(val(e, "damping"))
	p.damping_min = dm.x
	p.damping_max = maxf(dm.x, dm.y)
	var ra := _rng2(val(e, "radial"))
	p.radial_accel_min = ra.x
	p.radial_accel_max = maxf(ra.x, ra.y)
	var sc := _rng2(val(e, "scale"), Vector2.ONE)
	p.scale_amount_min = sc.x
	p.scale_amount_max = maxf(sc.x, sc.y)
	p.scale_amount_curve = curve(val(e, "scale_curve"))
	var an := _rng2(val(e, "angle"))
	p.angle_min = an.x
	p.angle_max = maxf(an.x, an.y)
	var sp := _rng2(val(e, "spin"))
	p.angular_velocity_min = sp.x
	p.angular_velocity_max = maxf(sp.x, sp.y)
	p.color_ramp = gradient(val(e, "colors"))
	p.particle_flag_align_y = bool(val(e, "align")) or mat == "spark"
	p.mesh = mesh(str(val(e, "mesh")))
	p.material_override = material(mat, bool(val(e, "billboard")))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if not playing:
		return
	_t += delta
	var ems: Array = def(effect).get("emitters", [])
	for i in _emitters.size():
		if not _started[i] and i < ems.size() and _t >= float(val(ems[i], "delay")):
			_started[i] = true
			if bool(val(ems[i], "on")) and (emitting or not attached):
				(_emitters[i] as CPUParticles3D).restart()
	if not attached:
		var dur := float(def(effect).get("duration", 1.0))
		if _t >= dur:
			for p in _emitters:
				if not (p as CPUParticles3D).one_shot:
					(p as CPUParticles3D).emitting = false
	if _light:
		var l: Dictionary = def(effect).get("light", {})
		var k := clampf(1.0 - _t / maxf(float(l.get("life", 0.5)), 0.01), 0.0, 1.0)
		_light.light_energy = float(l.get("energy", 0.0)) * k * k
		_light.omni_range = float(l.get("range", 20.0)) * scale_k
		_light.visible = k > 0.0
	if not attached and _t >= _life:
		_finish()


## A one-shot done: hidden and pooled for the next (or freed past the pool's size).
func _finish() -> void:
	playing = false
	for p in _emitters:
		(p as CPUParticles3D).emitting = false
	visible = false
	if keep:
		return
	var list: Array = _pool.get(effect, [])
	if list.size() >= POOL_MAX:
		queue_free()
		return
	list.append(self)
	_pool[effect] = list
	process_mode = Node.PROCESS_MODE_DISABLED


# --- Materials and meshes (shared) ------------------------------------------------

static func material(kind: String, billboard := true) -> Material:
	var key := kind + ("" if billboard else "/flat")
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	match kind:
		"smoke":
			m.shader = SMOKE
		"debris":
			m.shader = DEBRIS
		_:
			m.shader = ADD
			m.set_shader_parameter("kind", maxi(0, ["glow", "fire", "spark", "ring"].find(kind)))
			m.render_priority = 1   # (light over smoke: added after the blended ones)
	if kind != "debris":
		m.set_shader_parameter("billboard", billboard)
	_mats[key] = m
	return m


static func mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m: Mesh
	match kind:
		"streak":
			var q := QuadMesh.new()
			q.size = Vector2(0.12, 1.0)
			m = q
		"shard":
			m = _shard()
		_:
			var q := QuadMesh.new()
			q.size = Vector2.ONE
			m = q
	_meshes[kind] = m
	return m


## A jagged shard of plate (debris): a flattened, uneven octahedron, flat-shaded.
static func _shard() -> Mesh:
	var pts := [Vector3(0.5, 0.05, 0.1), Vector3(-0.45, -0.04, -0.12), Vector3(0.1, 0.12, 0.5), Vector3(-0.08, -0.1, -0.42),
		Vector3(0.05, 0.22, -0.05), Vector3(-0.04, -0.2, 0.06)]
	var faces := [[4, 0, 2], [4, 2, 1], [4, 1, 3], [4, 3, 0], [5, 2, 0], [5, 1, 2], [5, 3, 1], [5, 0, 3]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = pts[f[0]]
		var b: Vector3 = pts[f[1]]
		var c: Vector3 = pts[f[2]]
		var n := (b - a).cross(c - a).normalized()
		for v in [a, c, b]:
			st.set_normal(-n)
			st.add_vertex(v)
	return st.commit()


## The materials drawn once (CosmosWarm, at the title: their shaders compiled, their
## pipelines made) - one emitter of each kind the effects use, in `parent` (`shader`:
## only that shader's - "add", "smoke" or "debris": one compile a frame).
static func warm_into(parent: Node, shader := "") -> void:
	var seen := {}
	for name in names():
		for e in def(name).get("emitters", []):
			if not e is Dictionary:
				continue
			var m := str(val(e, "material"))
			if shader != "" and shader != (m if m in ["smoke", "debris"] else "add"):
				continue
			var key := "%s|%s|%s" % [val(e, "material"), val(e, "billboard"), val(e, "mesh")]
			if seen.has(key):
				continue
			seen[key] = true
			var p := CPUParticles3D.new()
			var w := (e as Dictionary).duplicate()
			w["amount"] = 2
			w["one_shot"] = false
			w["lifetime"] = 1.0
			w["on"] = true
			configure(p, w)
			p.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0)
			p.emitting = true
			p.preprocess = 0.5
			parent.add_child(p)
