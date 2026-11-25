class_name CosmosMining
extends Node3D
## Mining in the 3D game (Cosmos; the rules: Mining, as in the 2D game): fire
## with your sights on an asteroid within RANGE and your ship cuts it with its
## mining beam instead of its guns - the rock becomes your target (T on one
## does too). A targeted rock near you is scanned (SCAN_TIME): its minerals
## and its veins show (the HUD marks them on the rock as it tumbles). The
## beam cuts the vein nearest your sights: it heats - below the green band
## it cuts slowly, in it at full speed with resonance building, above it it
## strains, and at the top the vein fractures (a share lost as rubble). Let
## go and it cools. An unscanned rock gives only rubble. What's cut goes into
## the hold as fragments (a refinery makes minerals of them), until it's full.
## The rock is carved as it's mined (CosmosRocks.carve): each vein cut sinks
## into a pit, fractures blow chunks out, bulk hacking leaves craters where the
## beam hits; mined out, it's gone.

const RANGE := 1500.0
const SCAN_TIME := 2.0
const SCAN_REACH := 3000.0

var cosmos: Node
var field: CosmosRocks
var rock := -1
var proxy: Node3D                # the target the HUD shows (at the rock's middle)
var vein := -1
var last := ""                   # what the beam did last: cut / fracture / empty / bulk / full / far
var scan_t := 0.0
var cut := {}                    # mineral -> fragments cut from this rock
var active := false              # the beam on (this frame)
var hit_at := Vector3.ZERO

var _beam: MeshInstance3D
var _flare: MeshInstance3D
var _mat: StandardMaterial3D
var _sparks: Fx
var _t := 0.0
var _said := {}


## The beam's material: one for the run (its shader isn't made again each system).
static var _beam_mat: StandardMaterial3D


static func beam_mat() -> StandardMaterial3D:
	if _beam_mat == null:
		_beam_mat = StandardMaterial3D.new()
		_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_beam_mat.albedo_color = Color(1.0, 0.25, 0.15, 0.9)
		_beam_mat.emission_enabled = true
		_beam_mat.emission = Color(1.0, 0.18, 0.1) * 3.0
	return _beam_mat


func _ready() -> void:
	name = "Mining"
	_mat = beam_mat()
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	_beam.mesh = cyl
	_beam.material_override = _mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	_flare = MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	sp.radial_segments = 10
	sp.rings = 5
	_flare.mesh = sp
	_flare.material_override = _mat
	_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flare.visible = false
	add_child(_flare)
	_sparks = Fx.attach("mining_sparks", self)   # (sparks, a glow and rock dust where it cuts: data/effects.json)
	if _sparks:
		_sparks.emitting = false


## The rock under the sights (from `o` along `dir`): [field, rock, distance] or [].
func rock_under(o: Vector3, dir: Vector3, reach: float) -> Array:
	var best: Array = []
	for f: CosmosRocks in cosmos.fields:
		if f.global_position.distance_to(o) > CosmosRocks.SPREAD * 2.0 + reach:
			continue
		var h := f.ray(o, dir, reach if best.is_empty() else float(best[2]))
		if not h.is_empty():
			best = [f, h[0], h[1]]
	return best


## Rock `i` of field `f` your target (its proxy - a node at its middle).
func lock(f: CosmosRocks, i: int) -> void:
	if f == field and i == rock and is_instance_valid(proxy):
		cosmos.target = proxy
		return
	_drop_proxy()
	field = f
	rock = i
	vein = -1
	cut = {}
	scan_t = 0.0
	proxy = Node3D.new()
	proxy.name = "%s asteroid" % f.kind.capitalize()
	proxy.set_meta("rock_radius", float(f.rocks[i][1]))
	f.add_child(proxy)
	proxy.position = f.rocks[i][0]
	cosmos.target = proxy


func _drop_proxy() -> void:
	if is_instance_valid(proxy):
		if cosmos.target == proxy:
			cosmos.target = null
		proxy.queue_free()
	proxy = null
	field = null
	rock = -1


func rock_state() -> Dictionary:
	return field.state(rock) if field and rock >= 0 else {}


## Every frame (the ship flying): the scan, and the beam if you're firing at a
## rock - true while it mines (the guns hold their fire).
func step(delta: float, firing: bool) -> bool:
	active = false
	_t += delta
	if is_instance_valid(proxy) and cosmos.target != proxy:
		_drop_proxy()   # (another target picked)
	if field and rock >= 0 and float(field.rocks[rock][1]) <= 0.0:
		_drop_proxy()   # (mined out)
	var ship: Node3D = cosmos.ship
	# The scan: a targeted rock in reach.
	if field and rock >= 0:
		var st := rock_state()
		if not st["scanned"] and field.to_global(field.rocks[rock][0]).distance_to(ship.global_position) < SCAN_REACH:
			scan_t += delta
			if scan_t >= SCAN_TIME:
				st["scanned"] = true
				field.mined(rock)
				cosmos.hud.flash("Scanned: %s" % _comp_text(st))
	if firing:
		var cam: Camera3D = cosmos.cam
		var h := rock_under(cam.global_position, -cam.global_basis.z, RANGE + 600.0)
		if not h.is_empty():
			lock(h[0], h[1])
			if _mine(delta, cam.global_position - cam.global_basis.z * float(h[2])):
				_show(true)
				return true
	_show(false)
	return false


func _mine(delta: float, sight: Vector3) -> bool:
	var ship: Node3D = cosmos.ship
	var centre := field.to_global(field.rocks[rock][0])
	var r: float = field.rocks[rock][1]
	if centre.distance_to(ship.global_position) - r > RANGE:
		last = "far"
		_say("far", "Too far to mine - close within %d m" % int(RANGE))
		return false
	var st := rock_state()
	var data: Node = CosmosGame.data
	var up: Variant = data.get("upgrades")
	var speed := 1.0 + Upgrades.mod(up, "ship", "mining_speed")
	var yield_k := Upgrades.mod(up, "ship", "mining_yield")
	if st["scanned"]:
		if vein < 0 or vein >= st["veins"].size() or int(st["veins"][vein]["units"]) <= 0:
			vein = _vein_near(st, sight)
		if vein < 0:
			field.mined(rock)
			return false
		var v: Dictionary = st["veins"][vein]
		if data.room_for(Mining.frag_id(v["mineral"])) <= 0:
			last = "full"
			_say("full", "Cargo hold full - refine or sell what you carry")
			return false
		hit_at = field.vein_at(rock, v)
		last = _cut(st, v, delta, speed, yield_k)
		if last == "fracture":
			_say("fracture", "The vein fractured - too hot! Let it cool into the green")
		elif last == "empty":
			vein = -1
	else:
		if data.room_for(Mining.frag_id("rubble")) <= 0:
			last = "full"
			_say("full", "Cargo hold full - refine or sell what you carry")
			return false
		hit_at = centre + (sight - centre).normalized() * r * 0.8
		st["dmg"] = float(st["dmg"]) + Mining.RATE * 0.35 * delta
		while float(st["dmg"]) >= 1.0 and int(st["ore_left"]) > 0:
			st["dmg"] = float(st["dmg"]) - 1.0
			st["ore_left"] = int(st["ore_left"]) - 1
			_take("rubble", 1)
			# (the beam's crater where it hits)
			var u := field.to_unit(rock, field.to_local(hit_at))
			field.carve(rock, field.unit_surface(rock, u.normalized()), 0.2, 0.05)
		last = "bulk"
		_say("bulk", "Hacking at bulk rock: rubble only - target it (T) and stay near while it's scanned")
		if int(st["ore_left"]) <= 0:
			field.mined(rock)
	return true


## The laser on vein `v` (the 2D game's rule): heat, the band, resonance, fracture.
func _cut(st: Dictionary, v: Dictionary, delta: float, speed: float, yield_k: float) -> String:
	if int(v["units"]) <= 0:
		return "empty"
	var hard: float = float(Mining.MINERALS.get(v["mineral"], {"hard": 1.0})["hard"])
	v["heat"] = float(v["heat"]) + (Mining.HEAT * hard + Mining.COOL) * delta   # (it cools all the while: cool())
	var heat := float(v["heat"])
	if heat >= 1.0:
		var lost := maxi(1, int(int(v["units"]) * Mining.FRACTURE_LOSS))
		v["units"] = int(v["units"]) - lost
		st["ore_left"] = maxi(0, int(st["ore_left"]) - lost)
		v["heat"] = 0.45
		v["res"] = 1.0
		_take("rubble", mini(3, lost))
		# (a chunk blown out beside the pit)
		var d := (CosmosRocks.vein_dir(v) + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.5).normalized()
		field.carve(rock, field.unit_surface(rock, d), 0.22 + randf() * 0.12, 0.1 + randf() * 0.08)
		_pit(st, v)
		field.mined(rock)
		return "fracture"
	if Mining.in_band(heat):
		v["res"] = minf(Mining.RESONANCE_MAX, float(v["res"]) + Mining.RESONANCE_RATE * delta)
	else:
		v["res"] = 1.0
	v["acc"] = float(v["acc"]) + Mining.cut_rate(heat) * Mining.RATE * float(v["res"]) * speed * delta
	var out := ""
	while float(v["acc"]) >= 1.0 and int(v["units"]) > 0:
		v["acc"] = float(v["acc"]) - 1.0
		v["units"] = int(v["units"]) - 1
		st["ore_left"] = maxi(0, int(st["ore_left"]) - 1)
		_take(str(v["mineral"]), 2 if randf() < yield_k else 1)
		out = "cut"
	if out != "":
		_pit(st, v)
		field.mined(rock)
	return out if int(v["units"]) > 0 else "empty"


## The vein's pit: deeper and wider the more of it is gone (its key: its index).
func _pit(st: Dictionary, v: Dictionary) -> void:
	var gone := sqrt(1.0 - float(v["units"]) / maxf(1.0, float(v["max"])))   # (it shows from the first cuts)
	var w := float(v.get("len", 0.35))
	field.carve(rock, field.unit_surface(rock, CosmosRocks.vein_dir(v)), 0.14 + w * 0.5 + gone * 0.22, 0.04 + gone * 0.5, vein)


## Every vein of the rocks being worked cools (fire or not).
func cool(delta: float) -> void:
	if field == null or rock < 0:
		return
	for v in rock_state()["veins"]:
		if float(v["heat"]) > 0.0:
			v["heat"] = maxf(0.0, float(v["heat"]) - Mining.COOL * delta)


func _take(mineral: String, n: int) -> void:
	var id := Mining.frag_id(mineral)
	CosmosGame.data.add_item(id, n)
	cut[mineral] = int(cut.get(mineral, 0)) + n


func _vein_near(st: Dictionary, at: Vector3) -> int:
	var best := -1
	var bd := INF
	for k in st["veins"].size():
		var v: Dictionary = st["veins"][k]
		if int(v["units"]) <= 0:
			continue
		var d := field.vein_at(rock, v).distance_to(at)
		if d < bd:
			bd = d
			best = k
	return best


func _comp_text(st: Dictionary, most := 99) -> String:
	var parts: Array = []
	var comp: Dictionary = st["comp"]
	var ms: Array = comp.keys()
	ms.sort_custom(func(a, b): return comp[a] > comp[b])
	for m in ms.slice(0, most):
		parts.append("%s %d%%" % [Items.ITEMS.get(m, {}).get("name", m), roundi(float(comp[m]) * 100.0)])
	return ", ".join(parts)


func comp_text() -> String:
	var st := rock_state()
	return _comp_text(st, 3) if not st.is_empty() and st["scanned"] else ""


func _say(what: String, text: String) -> void:
	if Time.get_ticks_msec() - int(_said.get(what, -100000)) > 5000:
		_said[what] = Time.get_ticks_msec()
		cosmos.hud.flash(text)


## The beam: from the ship's nose to where it cuts, flickering; a flare there.
func _show(on: bool) -> void:
	active = on
	_beam.visible = on
	_flare.visible = on
	if _sparks:
		_sparks.emitting = on
	if not on:
		return
	var ship: Node3D = cosmos.ship
	var nose: Vector3 = ship.global_position - ship.global_basis.z * 14.0 - ship.global_basis.y * 1.5
	var d := hit_at - nose
	var L := d.length()
	if L < 0.5:
		_beam.visible = false
		return
	var y := d / L
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var fl := (0.8 + 0.35 * sin(_t * 47.0) * sin(_t * 31.0)) * (1.0 + L * 0.006)   # (thicker the farther: seen from behind the ship)
	_beam.global_transform = Transform3D(Basis(x * fl, y * L, z * fl), nose + d * 0.5)
	var hot := 1.0
	var st := rock_state()
	if st.get("scanned", false) and vein >= 0 and vein < st["veins"].size():
		hot = 0.6 + float(st["veins"][vein]["heat"])
	_flare.global_transform = Transform3D(Basis().scaled(Vector3.ONE * (1.6 + 0.8 * fl) * hot), hit_at)
	if _sparks:
		_sparks.global_transform = Transform3D(Fx.basis_up(-y), hit_at)
