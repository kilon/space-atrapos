class_name CosmosNpcShip
extends Node3D
## Another ship in the 3D game's space (stage 4): a procedural hull
## (CosmosHull) of its kind - a trader plying between the system's stations
## and planets (on its own Hyperion drive between them: a streak across the
## sky), a patrol of the system's empire circling a station, or a pirate who
## comes for you: closing in, circling, firing its lasers (CosmosBolt, space
## speed) when its nose is on you. Shields soak hits and come back; the hull
## doesn't. At none it blows up (CosmosBoom).

const TURN := 1.1               # rad/s
const LASER_EVERY := 0.55
const LASER_DAMAGE := 9.0

var kind := "trader"
var hull_kind := "trader"      # (its build: CosmosHull.SIZE's kinds - the target view says it)
var cosmos: Node
var faction := ""
var shield := 60.0
var max_shield := 60.0
var hull := 80.0
var max_hull := 80.0
var dead := false
var velocity := Vector3.ZERO
var speed_max := 160.0
var reach := 12.0
var dest: Node3D = null          # a trader's next stop
var home: Node3D = null          # a patrol's station
var hostile := false
var label := ""
var _cruise := false
var _fire := 1.0
var _since_hit := 99.0
var _rng := RandomNumberGenerator.new()
var _orbit := 1.0
var _breakoff := 0.0             # (s left of breaking away from an attack run)
var _glows: Array = []
## Docking (traders): the station's pad it was given, and how far along:
## 1 flying over it, 2 setting down, 3 sitting on it, 4 lifting off.
var pad := {}
var rec_id := ""                 # a trader's: its record in the economy (Galaxy.traders) - its route, its people (People)
var _pad_phase := 0
var _pad_t := 0.0
var _pad_stay := 60.0          # (s on the pad: down its lift, unloading, back up)
var _down := 0.0               # (m its lift is down)
## Its landing gear (three legs) and stern ramp - made the first time it lands
## (CosmosNpcShip._make_gear): out on the pad, the ramp down in the port.
var _gear: Array = []            # [holder, strut, foot, length]
var _ramp: Node3D = null
var _ramp_len := 4.0
var _ramp_ang := 0.3
var _gear_k := 0.0               # (0 stowed - 1 down)
var _ramp_k := 0.0               # (0 shut - 1 down to the deck)
var _gear_shown := Vector2(-1, -1)
static var _gear_parts := {}
var interior: CosmosNpcInterior   # (its insides, walkable - made when you come near it in port)
## Hired (a town's local pilot - CosmosSandbox.hire_ride): its flight as a dictionary -
## state (arrive, wait, climb, out, transfer, in, descend, landed, leave), the planet and
## field it set out from (planet-local, as transforms), where it's going, its clock.
var hire := {}
var traffic: Object = null      # (a town's landing pad's ship: CosmosLandingField flies it - its round's schedule)

static var _glow_mats := {}


func setup(k: String, c: Node, seed: int, empire: String, hull_as := "") -> void:
	kind = k
	add_to_group("cam_solid")   # (the camera stops short of its parts)
	set_meta("cam_reach", 80.0)
	cosmos = c
	_rng.seed = seed
	faction = empire
	hostile = k == "pirate" or (k == "invader" and Galaxy.is_hostile_to_player(empire))
	var r := _rng.randf()
	var hk: String = {"trader": "trader" if r < 0.6 else ("freighter" if r < 0.85 else "hauler"), "patrol": "patrol", "invader": "patrol", "pirate": "pirate"}.get(k, "fighter")
	if hull_as != "":
		hk = hull_as   # (a build asked for: a local pilot's ship is a small trader)
	hull_kind = hk
	var whose := empire if k != "pirate" else "pirates"
	var nozzles := CosmosHull.build(self, _rng, hk, whose)
	reach = CosmosHull.size_of(hk, whose) * 11.0
	match k:
		"trader":
			max_shield = 80.0
			max_hull = 160.0 * CosmosHull.SIZE.get(hk, 1.0) * 0.5
			speed_max = 120.0
			label = "%s %s" % [Galaxy.EMPIRES.get(empire, {}).get("short", "Independent"), "hauler" if hk == "hauler" else "trader"]
			if hk == "hauler":
				speed_max = 80.0
		"patrol":
			max_shield = 120.0
			max_hull = 140.0
			speed_max = 200.0
			label = "%s patrol" % Galaxy.EMPIRES.get(empire, {}).get("short", "System")
		"pirate":
			max_shield = 50.0
			max_hull = 90.0
			speed_max = 210.0
			label = "Pirate raider"
		"invader":   # (an invasion fleet's warship, at the station it besieges: CosmosLaw)
			max_shield = 140.0
			max_hull = 190.0
			speed_max = 220.0
			label = "%s warship" % Galaxy.EMPIRES.get(empire, {}).get("short", "Enemy")
	shield = max_shield
	hull = max_hull
	name = label.replace(" ", "_")
	if not _glow_mats.has(whose):   # (its engines' light: the empire's lamps')
		var gm := ShaderMaterial.new()
		gm.shader = preload("res://shaders/world/glow.gdshader")
		gm.set_shader_parameter("tint", (EmpireKit.look(whose)["lamp"] as Color).lerp(Color(0.8, 0.9, 1.0), 0.25))
		gm.set_shader_parameter("intensity", 1.6)
		_glow_mats[whose] = gm
	for nz in nozzles:
		var g := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * reach * 0.3
		g.mesh = q
		g.material_override = _glow_mats[whose]
		g.position = nz
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		_glows.append(g)
	_orbit = 1.0 if _rng.randf() < 0.5 else -1.0


func up() -> Vector3:
	return global_basis.y


func hurt(dmg: float, _from: Vector3) -> void:
	if dead:
		return
	_since_hit = 0.0
	var s := minf(shield, dmg)
	shield -= s
	hull -= dmg - s
	if not hostile and cosmos:
		hostile = true   # (fired on: it fights back, or flees - traders run)
	if hull <= 0.0:
		dead = true
		if cosmos:
			cosmos.ship_destroyed(self)
		CosmosBoom.at(cosmos, global_position, reach)
		queue_free()


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if dead or cosmos == null:
		return
	_since_hit += delta
	if _since_hit > 4.0:
		shield = minf(max_shield, shield + 10.0 * delta)
	if not hire.is_empty():
		_hire_fly(delta)
		return
	if traffic != null:
		traffic.call("fly", self, delta)
		return
	if pad.is_empty() and (_gear_k > 0.0 or _ramp_k > 0.0):
		_gear_step(0.0, 0.0, delta)   # (off the pad: the ramp up, the legs in)
	if not pad.is_empty() and _pad_fly(delta):
		return
	var player: Node3D = cosmos.ship
	var want := -global_basis.z
	var spd := speed_max * 0.6
	if hostile and kind != "trader" and player and cosmos.walker == null and player.state == "fly":
		var to: Vector3 = player.global_position - global_position
		var d := to.length()
		# Attack runs: in at you firing, break away close (never stuck on you), come round again.
		var side := to.cross(global_basis.y).normalized() * _orbit
		if _breakoff > 0.0:
			_breakoff -= delta
			want = (-to / d + side * 0.5 + global_basis.y * 0.3).normalized()
			spd = speed_max * 1.3
		elif d < 220.0:
			_breakoff = _rng.randf_range(2.0, 3.8)
			_orbit = -_orbit
			want = (side - to / d).normalized()
			spd = speed_max * 1.3
		elif d > 900.0:
			want = to / d
			spd = speed_max * (4.0 if d > 4000.0 else 1.0)   # (closing in fast from afar)
		else:
			want = (to / d + side * 0.25).normalized()
			spd = speed_max
		_fire -= delta
		if _fire <= 0.0 and d < 1600.0 and (-global_basis.z).angle_to(to) < 0.18:
			_fire = LASER_EVERY * _rng.randf_range(0.8, 1.4)
			var lead: Vector3 = player.global_position + player.velocity * (d / CosmosBolt.SPACE_SPEED)
			var spread := 0.006
			var aim := (lead - global_position).normalized() + Vector3(_rng.randfn(0, spread), _rng.randfn(0, spread), _rng.randfn(0, spread))
			CosmosBolt.fire(cosmos, global_position - global_basis.z * reach * 0.6, aim, "enemy", LASER_DAMAGE, true)
	elif kind == "invader" and home and is_instance_valid(home):
		# The siege: round the station it besieges, in close to fire on it.
		var st := home as CosmosStation
		var to := st.global_position - global_position
		var d := to.length()
		var r := st.reach + 450.0
		var side := to.cross(st.global_basis.y).normalized() * _orbit
		want = (to / d * clampf((d - r) / 350.0, -1.0, 1.0) + side).normalized()
		spd = speed_max * (0.75 if d < r + 1500.0 else (4.0 if d > r + 6000.0 else 1.4))
		_fire -= delta
		if _fire <= 0.0 and d < r + 1600.0 and cosmos.law:
			_fire = _rng.randf_range(0.9, 1.8)
			var aim: Vector3 = cosmos.law.station_point(st)
			var p := st.to_global(aim)
			var b := CosmosBolt.fire(cosmos, global_position, (p - global_position).normalized(), "invader", LASER_DAMAGE, true)
			b.set_meta("st", st)
			b.set_meta("aim", aim)
			b.life = global_position.distance_to(p) / CosmosBolt.SPACE_SPEED + 0.5
	elif kind == "trader" and dest is CosmosGate and not hostile:
		var to := dest.global_position - global_position
		want = to.normalized()
		spd = clampf(to.length() * 0.4, speed_max, 30000.0)
		if to.length() < 260.0:
			cosmos.trader_jumped(self)   # (through the gate: on its way in the next system)
			return
	elif kind == "trader" and dest:
		var to := dest.global_position - global_position
		var d: float = to.length() - cosmos.radius_of(dest) - 400.0
		want = to.normalized()
		if hostile and player:
			want = (global_position - player.global_position).normalized()   # (fired on: it runs)
			spd = speed_max * 1.6
		elif dest is CosmosStation and pad.is_empty() and to.length() < (dest as CosmosStation).reach + 3000.0:
			var p: Dictionary = (dest as CosmosStation).free_pad(reach * 1.7, global_position)
			if not p.is_empty():
				p["owner"] = self
				pad = p
				_pad_phase = 1
			spd = speed_max
		elif dest is CosmosPlanet and cosmos.riding() == self and to.length() - (dest as CosmosPlanet).radius < HIRE_ARC + 600.0:
			cosmos.ride_lands(self)   # (a world, you aboard: down on its town's field to let you off - never gone with you)
			return
		elif d > 6000.0:
			spd = clampf(d * 0.4, speed_max, 30000.0)   # (its own Hyperion drive)
		elif d < 200.0 and rec_id == "":
			cosmos.trader_arrived(self)
			return
		else:
			spd = speed_max
	elif home:
		var to := home.global_position - global_position
		var d := to.length()
		var r: float = cosmos.radius_of(home) + 900.0
		var side := to.cross(Vector3.UP).normalized()
		want = (to.normalized() * clampf((d - r) / 400.0, -1.0, 1.0) + side * 0.8).normalized()
		spd = speed_max * 0.5
	_turn_and_fly(want, spd, delta)
	cosmos.bump_npc(self)


## Flies its pad's approach: over it, down onto it, a while there, off it.
## True when it moved itself (sitting, setting down, lifting off).
func _pad_fly(delta: float) -> bool:
	var st := dest as CosmosStation
	if hostile or st == null or not is_instance_valid(st):
		_leave_pad()
		return false
	var xf := st.pad_transform(pad)
	var u := xf.basis.y
	var rest := xf.origin + u * rest_height()
	match _pad_phase:
		1:   # (to a point over the pad)
			var above := rest + u * (250.0 + reach * 2.0)
			var to := above - global_position
			_gear_step(0.0, 0.0, delta)
			if to.length() < 25.0:
				_pad_phase = 2
			_turn_and_fly(to.normalized(), clampf(to.length() * 0.4, 20.0, speed_max * 1.5), delta)
			return true
		2:   # (level with the pad, down onto it)
			var level: Basis = Cosmos._level(Cosmos.pad_nose(xf), u)   # (square on the pad: nose to its top)
			global_basis = global_basis.slerp(level, minf(1.0, delta * 1.5)).orthonormalized()
			var h := (global_position - rest).dot(u)
			_gear_step(1.0 if h < 150.0 else 0.0, 0.0, delta)   # (the legs out for the touchdown)
			var side := (rest - global_position) - u * (rest - global_position).dot(u)
			velocity = side * 0.8 - u * clampf(h * 0.35, 2.0, 40.0)
			global_position += velocity * delta
			if h < 0.5:
				global_position = rest
				global_basis = level
				velocity = Vector3.ZERO
				_pad_phase = 3
				_pad_t = 0.0
				_pad_stay = _rng.randf_range(40.0, 90.0) if not has_meta("hired") else 180.0   # (a hired ride: time for you to walk off)
				if rec_id != "":   # (there: its cargo sold, a while in port - its people ashore)
					Galaxy.arrive_live(rec_id)
					var r: Dictionary = Galaxy.traders.get(rec_id, {})
					r["wait"] = _rng.randf_range(80.0, 160.0)
					r["pad"] = int(pad.get("id", 0))
					_pad_stay = float(r["wait"]) + Cosmos.LIFT_TIME + Cosmos.HATCH_TIME
			_engines_glow(0.6)
			return true
		3:   # (down the lift into the port's hall, shutters shut over it; unloading; back up)
			_pad_t += delta
			var lt := Cosmos.LIFT_TIME
			var ht := Cosmos.HATCH_TIME
			var up_at := _pad_stay - lt - ht   # (when the shutters start opening)
			var depth := Cosmos.LIFT_DEPTH * smoothstep(0.0, 1.0, _pad_t / lt)
			var hatch := clampf((_pad_t - lt * 0.6) / ht, 0.0, 1.0)
			if _pad_t > up_at:
				hatch = 1.0 - clampf((_pad_t - up_at) / ht, 0.0, 1.0)
				depth = Cosmos.LIFT_DEPTH * (1.0 - smoothstep(0.0, 1.0, (_pad_t - up_at - ht * 0.9) / lt))
			st.lower_pad(pad, depth)
			st.set_hatch(pad, hatch)
			_down = depth
			# (the ramp down once it's in the port - its people out, theirs in - and up before it rises)
			_gear_step(1.0, 1.0 if _pad_t > lt and _pad_t < up_at - 2.5 else 0.0, delta)
			global_position = rest - u * depth
			_engines_glow(0.0)
			if rec_id != "":   # (its time left in port - its people go back aboard before it)
				Galaxy.traders.get(rec_id, {})["wait"] = maxf(0.0, _pad_stay - _pad_t)
			if _pad_t >= _pad_stay:
				st.lower_pad(pad, 0.0)
				st.set_hatch(pad, 0.0)
				_down = 0.0
				_pad_phase = 4
				_pad_t = 0.0
				if rec_id != "":   # (its next run planned: where it goes from here)
					Galaxy.depart_live(rec_id)
					Galaxy.traders.get(rec_id, {}).erase("pad")
			return true
		4:   # (straight up, then on to its next stop)
			_pad_t += delta
			velocity = u * minf(5.0 + _pad_t * 8.0, 60.0)
			global_position += velocity * delta
			_gear_step(0.0 if _pad_t > 2.0 else 1.0, 0.0, delta)
			_engines_glow(0.6)
			if _pad_t > 8.0:
				_leave_pad()
				if rec_id == "" and cosmos.riding() == self:
					dest = cosmos.ride_next(self, st)   # (you're still aboard: somewhere it can set you down)
				else:
					dest = cosmos.leg_end(rec_id) if rec_id != "" else cosmos.trader_next(st)
				if dest == null:
					cosmos.trader_arrived(self)
			return true
	return false


## Already down on `p` of station `st` (a docked trader when you come into the
## system): on its lift in the port, its time in port left as its record says.
func park(st: CosmosStation, p: Dictionary) -> void:
	dest = st
	pad = p
	p["owner"] = self
	var r: Dictionary = Galaxy.traders.get(rec_id, {})
	r["pad"] = int(p.get("id", 0))
	var xf := st.pad_transform(p)
	global_transform = Transform3D(Cosmos._level(Cosmos.pad_nose(xf), xf.basis.y), xf.origin + xf.basis.y * (rest_height() - Cosmos.LIFT_DEPTH))
	_pad_phase = 3
	_pad_t = Cosmos.LIFT_TIME + Cosmos.HATCH_TIME
	_pad_stay = _pad_t + maxf(float(r.get("wait", 60.0)), 30.0) + Cosmos.LIFT_TIME + Cosmos.HATCH_TIME
	st.lower_pad(p, Cosmos.LIFT_DEPTH)
	st.set_hatch(p, 1.0)
	_down = Cosmos.LIFT_DEPTH
	_make_gear()
	_gear_k = 1.0
	_ramp_k = 1.0
	_gear_show()


func _leave_pad() -> void:
	if not pad.is_empty() and pad.get("owner") == self:
		pad["owner"] = null
		if _down > 0.0 and dest is CosmosStation and is_instance_valid(dest):   # (off the lift halfway: back up, shutters open)
			(dest as CosmosStation).lower_pad(pad, 0.0)
			(dest as CosmosStation).set_hatch(pad, 0.0)
	_down = 0.0
	pad = {}
	_pad_phase = 0


func _engines_glow(k: float) -> void:
	for g in _glows:
		if is_instance_valid(g):   # (its hull rebuilt: the old glows gone)
			(g as Node3D).visible = k > 0.05


func _exit_tree() -> void:
	_leave_pad()


func _turn_and_fly(want: Vector3, spd: float, delta: float) -> void:
	_engines_glow(1.0)
	# Turn toward `want`, fly along the nose.
	var f := -global_basis.z
	var ang := f.angle_to(want)
	if ang > 0.001:
		var axis := f.cross(want)
		if axis.length() < 0.001:
			axis = global_basis.y
		global_basis = (Basis(axis.normalized(), minf(ang, TURN * delta)) * global_basis).orthonormalized()
	velocity = velocity.move_toward(-global_basis.z * spd, maxf(spd, 80.0) * 1.2 * delta)
	global_position += velocity * delta


## How high its middle sits over a pad's deck, landed: its belly on its legs
## (the hull's own depth under its middle, and legs a little longer for a bigger ship).
var _rest_h := -1.0


func rest_height() -> float:
	if _rest_h < 0.0:
		_rest_h = -_hull_box().position.y + clampf(reach * 0.04, 1.2, 4.0)
	return _rest_h


## The hull's bounds in the ship's own space (its meshes: not the engines' glows, not the gear).
func _hull_box() -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.mesh is QuadMesh or mi.has_meta("gear"):
			continue
		var xf := Transform3D()
		var n: Node = mi
		while n != self and n != null:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box if not first else AABB(Vector3(-reach * 0.3, -reach * 0.15, -reach), Vector3(reach * 0.6, reach * 0.3, reach * 2.0))


## Three legs (one under the nose, two aft) from the belly down to the pad's
## deck, and a ramp hinged under the stern - sized to the hull. Shared meshes.
func _make_gear() -> void:
	if not _gear.is_empty():
		return
	if _gear_parts.is_empty():
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.3, 0.31, 0.34)
		metal.metallic = 0.7
		metal.roughness = 0.4
		var plate := StandardMaterial3D.new()
		plate.albedo_color = Color(0.46, 0.47, 0.5)
		plate.metallic = 0.6
		plate.roughness = 0.55
		var cy := CylinderMesh.new()
		cy.top_radius = 0.5
		cy.bottom_radius = 0.5
		cy.height = 1.0
		cy.radial_segments = 8
		cy.rings = 1
		_gear_parts = {"metal": metal, "plate": plate, "cyl": cy, "box": BoxMesh.new()}
	var hb := _hull_box()
	var deck := -rest_height()   # (the pad's deck under it, sitting: _pad_fly's rest)
	var top := hb.position.y + hb.size.y * 0.2   # (from inside the belly: no gap under a curved hull)
	var cx := hb.get_center().x
	var r := clampf(reach * 0.02, 0.25, 1.4)
	var hw := hb.size.x * 0.28
	var zf := hb.position.z + hb.size.z * 0.2
	var za := hb.end.z - hb.size.z * 0.22
	for at in [Vector3(cx, top, zf), Vector3(cx - hw, top, za), Vector3(cx + hw, top, za)]:
		var holder := Node3D.new()
		holder.position = at
		add_child(holder)
		var strut := _gear_part("cyl", "metal", Vector3(r * 2.0, 1.0, r * 2.0))
		holder.add_child(strut)
		var foot := _gear_part("box", "metal", Vector3(r * 5.0, r * 0.6, r * 5.0))
		holder.add_child(foot)
		_gear.append([holder, strut, foot, maxf(top - deck, 0.5)])
	# The ramp: hinged at the stern's sill (its insides' deck: low in the hull, headroom over it), down to the pad's deck at a walkable slope.
	var sill := hb.position.y + hb.size.y * 0.18
	var drop := maxf(sill - deck, 0.5)
	_ramp_len = clampf(drop / sin(0.42), 3.0, maxf(hb.size.z * 0.45, 3.0))
	_ramp_ang = asin(clampf(drop / _ramp_len, 0.0, 1.0))
	_ramp = Node3D.new()
	_ramp.position = Vector3(cx, sill, hb.end.z - hb.size.z * 0.04)
	add_child(_ramp)
	var plank := _gear_part("box", "plate", Vector3(clampf(hb.size.x * 0.3, 2.4, 4.0), maxf(r * 0.5, 0.2), _ramp_len))
	plank.position = Vector3(0, 0, _ramp_len * 0.5)
	plank.visible = true   # (shown and hidden with its hinge)
	_ramp.visible = false
	_ramp.add_child(plank)


func _gear_part(mesh: String, mat: String, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _gear_parts[mesh]
	mi.material_override = _gear_parts[mat]
	mi.scale = size
	mi.set_meta("gear", true)
	mi.visible = false
	return mi


## The gear toward `g` (legs) and `rmp` (ramp): 0 stowed, 1 down - about 2 s each way.
func _gear_step(g: float, rmp: float, delta: float) -> void:
	if (g > 0.0 or rmp > 0.0) and _gear.is_empty():
		_make_gear()
	if _gear.is_empty():
		return
	_gear_k = move_toward(_gear_k, g, delta * 0.5)
	_ramp_k = move_toward(_ramp_k, rmp, delta * 0.45)
	_gear_show()


func _gear_show() -> void:
	var now := Vector2(_gear_k, _ramp_k)
	if now == _gear_shown:
		return   # (nothing moved: nothing set)
	_gear_shown = now
	var k := smoothstep(0.0, 1.0, _gear_k)
	for g in _gear:
		var strut: MeshInstance3D = g[1]
		var foot: MeshInstance3D = g[2]
		var l: float = g[3] * k
		strut.visible = k > 0.02
		foot.visible = k > 0.02
		strut.scale.y = maxf(l, 0.01)
		strut.position.y = -l * 0.5
		foot.position.y = -l + foot.scale.y * 0.5
	var rk := smoothstep(0.0, 1.0, _ramp_k)
	_ramp.visible = rk > 0.02
	if interior:
		interior.set_cut(rk > 0.3)   # (the doorway in the hull only while its ramp's down)
	_ramp.rotation.x = lerpf(-PI * 0.5, _ramp_ang, rk)   # (folded up against the stern - down to the deck)


## Its insides, walkable (made on a worker the first time you come near it in port).
func make_interior() -> CosmosNpcInterior:
	if interior == null and _ramp != null:
		interior = CosmosNpcInterior.new()
		add_child(interior)
		interior.setup(self, faction)
	return interior


## The doorway through its hull (ship space) while its ramp's down and its insides are in -
## open to walk through, look through, shoot through (CosmosHullGrid's cut); else none.
func door_box() -> AABB:
	if interior == null or not interior.ok or _ramp_k < 0.3:
		return AABB()
	return interior.door


## Its time in port nearly out: its ramp about to close (anyone aboard walked off first).
func leaving_soon() -> bool:
	return _pad_phase != 3 or _pad_t > _pad_stay - Cosmos.LIFT_TIME - Cosmos.HATCH_TIME - 6.0


# --- Hired: a local pilot's ride -----------------------------------------------------------

const HIRE_ALT := 1400.0        # m: how high it comes in from and climbs to over a field
const HIRE_ARC := 4000.0        # m over the ground: round the planet to the side facing where it's going
const HIRE_WAIT := 240.0        # s it waits on the field for you
const PILOT_WAIT := 60.0        # s with you aboard it waits for its pilot to be seated, at most (a stuck pilot never strands the ride)


## Down to the field `field` (planet-local transform: its basis level, x along the
## field, origin on its deck) of `pl`, its ramp down for you; then (aboard) to `to`:
## {"pl": planet, "field": transform} (another world's town) or {"station": node}.
func hire_ride(pl: CosmosPlanet, field: Transform3D, to: Dictionary) -> void:
	_make_gear()
	hire = {"state": "arrive", "t": 0.0, "pl": pl, "field": field, "to": to}
	var wf := pl.global_transform * field   # (the field in the world's frame now: its world turns)
	global_transform = Transform3D(wf.basis, wf.origin + wf.basis.y * HIRE_ALT + wf.basis.z * 600.0)


func hire_state() -> String:
	return str(hire.get("state", ""))


## Down on a field with its ramp down (to walk on or off).
func hire_open() -> bool:
	return hire_state() in ["wait", "landed"] and _ramp_k > 0.99


func _rest_xf(pl: CosmosPlanet, field: Transform3D) -> Transform3D:
	var wf := pl.global_transform * field
	return Transform3D(wf.basis, wf.origin + wf.basis.y * rest_height())


func _hire_fly(delta: float) -> void:
	hire["t"] = float(hire["t"]) + delta
	var t: float = hire["t"]
	var st := hire_state()
	var aboard: bool = cosmos != null and cosmos.riding() == self
	var pl: CosmosPlanet = hire["pl"]
	var field: Transform3D = hire["field"]
	if not is_instance_valid(pl):
		hire = {}
		queue_free()
		return
	var to: Dictionary = hire["to"]
	match st:
		"arrive", "descend":   # (down onto the field, legs out near the ground)
			var k := smoothstep(0.0, 1.0, minf(t / 12.0, 1.0))
			var rest := _rest_xf(pl, field)
			var from := rest.origin + rest.basis.y * HIRE_ALT + rest.basis.z * 600.0
			global_transform = Transform3D(rest.basis, from.lerp(rest.origin, k))
			_gear_step(1.0 if k > 0.7 else 0.0, 0.0, delta)
			_engines_glow(0.6)
			if k >= 1.0:
				hire["state"] = "wait" if st == "arrive" else "landed"
				hire["t"] = 0.0
		"wait":   # (on the field, its ramp down: waiting for you - and its pilot, walking over to it)
			global_transform = _rest_xf(pl, field)
			_gear_step(1.0, 1.0, delta)
			_engines_glow(0.0)
			var pilot: Variant = hire_pilot()
			if pilot and _ramp_k > 0.99 and pilot.ride != self:
				make_interior()
				pilot.board_ride(self)
			if aboard and interior and interior.ok and interior.to_local(cosmos.walker.global_position).z < interior.z_aft - 1.5:
				hire["aboard_t"] = float(hire.get("aboard_t", 0.0)) + delta
				var ready: bool = pilot == null or pilot.seated() or float(hire["aboard_t"]) > PILOT_WAIT + float(hire.get("pilot_walk", 0.0))   # (a pilot hired in the town: his walk back to it besides)
				if float(hire["aboard_t"]) > 2.5 and ready:   # (you're in, clear of the ramp, its pilot in his seat: off)
					if pilot:
						pilot.drop_ride()   # (if he never made it aboard: back to his town)
					hire["state"] = "climb"
					hire["t"] = 0.0
			elif t > HIRE_WAIT and not aboard:
				if pilot:
					pilot.drop_ride()
				hire["state"] = "leave"
				hire["t"] = 0.0
		"climb":   # (the ramp up, straight up off the field)
			_gear_step(0.0, 0.0, delta)
			var k := smoothstep(0.0, 1.0, clampf((t - 2.5) / 9.0, 0.0, 1.0))
			var rest := _rest_xf(pl, field)
			global_transform = Transform3D(rest.basis, rest.origin + rest.basis.y * HIRE_ALT * k)
			_engines_glow(0.6)
			if k >= 1.0:
				hire["state"] = "out"
				hire["t"] = 0.0
		"out", "in":   # (round the planet, over its ground, to face the way it's going / from it)
			var here: CosmosPlanet = pl if st == "out" else to["pl"]
			var fu: Vector3 = here.global_basis * (field if st == "out" else to["field"] as Transform3D).basis.y
			var aim := _hire_aim()
			var dir := (aim - here.global_position).normalized() if st == "out" else (_hire_from() - here.global_position).normalized()
			var k := smoothstep(0.0, 1.0, minf(t / 9.0, 1.0))
			var a: Vector3 = fu.slerp(dir, k) if st == "out" else dir.slerp(fu, k)
			var r: float = here.radius + lerpf(HIRE_ALT, HIRE_ARC, 1.0 - absf(k * 2.0 - 1.0)) if st == "out" else here.radius + lerpf(HIRE_ARC, HIRE_ALT, k)
			var p := here.global_position + a.normalized() * r
			_face(p - global_position, a)
			global_position = p
			_engines_glow(0.6)
			if k >= 1.0:
				hire["state"] = "transfer" if st == "out" else "descend"
				hire["t"] = 0.0
				if st == "out":
					hire["from"] = global_position - pl.global_position
					hire["dur"] = clampf(global_position.distance_to(_hire_aim()) / 12000.0, 6.0, 40.0)
				else:
					hire["pl"] = to["pl"]
					hire["field"] = to["field"]
		"transfer":   # (across the system on its drive: a smooth run from its world to the other)
			var dur: float = hire["dur"]
			var k := smoothstep(0.0, 1.0, minf(t / dur, 1.0))
			var a: Vector3 = pl.global_position + (hire["from"] as Vector3)
			var p := a.lerp(_hire_aim(), k)
			_face(p - global_position, global_basis.y)
			global_position = p
			_engines_glow(0.8)
			if k >= 1.0:
				if to.has("gate"):   # (another system: through the gate - you aboard, with it; else gone)
					hire["state"] = "jumped"
					if cosmos and cosmos.riding() == self:
						cosmos.ride_jump(self, str(to["sys"]))
					else:
						cosmos.npc_ships.erase(self)
						queue_free()
				elif to.has("station"):   # (a station: its pads and its port, as any trader's)
					set_meta("home", pl)   # (stay aboard and it takes you back to its pilot's town)
					hire = {}
					dest = to["station"]
					set_meta("hired", true)
				else:
					hire["state"] = "in"
					hire["t"] = 0.0
		"landed":   # (there: its ramp down until you've walked off, then away)
			global_transform = _rest_xf(pl, field)
			_gear_step(1.0, 1.0, delta)
			_engines_glow(0.0)
			if aboard:
				hire["t"] = 0.0
			elif t > 12.0:
				hire["state"] = "leave"
				hire["t"] = 0.0
		"leave":   # (up and gone)
			_gear_step(0.0, 0.0, delta)
			var rest := _rest_xf(pl, field)
			var k := clampf((t - 2.5) / 10.0, 0.0, 1.0)
			global_transform = Transform3D(rest.basis, rest.origin + rest.basis.y * HIRE_ALT * 2.5 * k * k)
			_engines_glow(0.6)
			if k >= 1.0 and not aboard:
				if cosmos:
					cosmos.npc_ships.erase(self)
				queue_free()


## Its pilot (CosmosNpc, the town's local pilot who was hired - or, gone with his
## town's people while you were away, the one at its field now), or null.
func hire_pilot() -> Variant:
	var p: Variant = hire.get("pilot")
	if is_instance_valid(p) and not p.is_queued_for_deletion():
		return p
	hire.erase("pilot")
	var t: Variant = hire.get("town")
	if hire_state() != "wait" or not is_instance_valid(t) or cosmos == null:
		return null
	for x in cosmos.citizens:
		if is_instance_valid(x) and x.town == t and x.role == "pilot" and x.ride == null:
			hire["pilot"] = x
			return x
	return null


## Where its run across the system ends: over the far side of the other world (or off the station).
func _hire_aim() -> Vector3:
	var to: Dictionary = hire["to"]
	var from := _hire_from()
	if to.has("gate"):   # (through its ring)
		var g: Node3D = to["gate"]
		return g.global_position if is_instance_valid(g) else from
	if to.has("station"):
		var st: Node3D = to["station"]
		var r: float = cosmos.radius_of(st) + 2500.0 if cosmos else 3000.0
		return st.global_position + (from - st.global_position).normalized() * r
	var dp: CosmosPlanet = to["pl"]
	return dp.global_position + (from - dp.global_position).normalized() * (dp.radius + HIRE_ARC)


func _hire_from() -> Vector3:
	var pl: CosmosPlanet = hire["pl"]
	if not is_instance_valid(pl) or pl == (hire["to"] as Dictionary).get("pl"):
		return global_position   # (come in from space, not from another world: from where it is)
	return pl.global_position


func _face(go: Vector3, up_: Vector3) -> void:
	if go.length() < 0.01:
		return
	var f := go.normalized()
	var u := (up_ - f * up_.dot(f)).normalized()
	if u.length() < 0.5:
		u = global_basis.y
	global_basis = global_basis.slerp(Basis.looking_at(f, u), 0.15).orthonormalized()
