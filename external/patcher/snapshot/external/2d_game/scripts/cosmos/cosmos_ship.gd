class_name CosmosShip
extends Node3D
## Your ship in the 3D game (Cosmos): a procedural hull (a lofted fuselage,
## swept wings, twin engines, a canopy, fins - in your empire's colours) and
## its flight: the mouse is a virtual stick (its offset from the middle sets
## the pitch and yaw rates; C or the middle button centres it), A / D roll,
## W / S the throttle (it stays where you leave it; X stops), Shift boosts.
## J engages the Hyperion drive: after a two-second charge it races across
## the system - to your target (T) if you have one, steering itself there
## while you leave the stick alone - its top speed a share of the distance
## left (up to 250 km/s: any planet in well under a minute), so it slows by
## itself as you arrive and drops you out HYPER_ARRIVE short of it; passing
## close to anything else slows it too, and it drops out rather than hit it. Flight assist always steers the velocity toward the nose.
## Bumps: the ground (it skims along it), stations, rocks, the star.

const MAX_SPEED := 180.0        # m/s, full throttle
const BOOST := 2.6              # times that with Shift
const ACCEL := 70.0             # m/s2
const RATES := Vector3(1.25, 0.8, 2.2)   # pitch, yaw, roll (rad/s at full stick)
const CRUISE_CHARGE := 2.0      # s (the Hyperion drive spooling up)
const CRUISE_MIN := 800.0       # m/s
const CRUISE_MAX := 250000.0    # m/s
const CRUISE_SHARE := 0.8       # top speed = this x the distance left (to the target, else to the nearest thing) a second
const CRUISE_DROP := 450.0      # m: drop out this close to something in the way (an exclusion zone)
const HYPER_ARRIVE := 1600.0    # m: dropped out this far from the target's surface
const ASSIST := 1.3             # rad/s: turning to the target by itself
const ALIGN := 0.2              # rad: the drive engages only with the nose this close to the target
const DEADZONE := 0.06
const HULL_R := 20.0            # m (bumps)
const SCALE := 2.6              # the hull's design scaled up: ~49 m long, big enough to walk inside

var velocity := Vector3.ZERO
var throttle := 0.0             # -0.25 .. 1
var stick := Vector2.ZERO       # x right, y down (mouse); |stick| <= 1
var roll := 0.0
var boosting := false
var cruise := 0                 # 0 off, 1 charging, 2 engaged
var cruise_t := 0.0
var _aim := Vector3.ZERO        # (the way the drive's assist steers: to the target, round what's between)
var well: Array = [1.0, null]   # (the gravity slowing the Hyperion drive: [factor, body] - the HUD)
var cosmos: Node                # (Cosmos: clearance, bumps)
var control := true             # (off: tests drive it, menus open)
var _ang := Vector3.ZERO
var _headless := DisplayServer.get_name() == "headless"
var _glows: Array = []
var _plumes: Array = []
## The input for this frame when not read from the devices (tests): {throttle, stick, roll, boost}.
var drive := {}
## Combat (stage 4): shields soak hits and come back after a moment; the hull
## doesn't. The left button fires twin lasers from the wingtips at what the
## sights are on (leading a targeted ship).
const MAX_SHIELD := 120.0
const MAX_HULL := 200.0
const LASER_EVERY := 0.14
const LASER_DAMAGE := 14.0
var max_shield := MAX_SHIELD    # (from your fittings - apply_upgrades)
var max_hull := MAX_HULL
var laser_damage := LASER_DAMAGE
var speed_k := 1.0
var shield := MAX_SHIELD
var hull := MAX_HULL
var trigger := false
var reach := 18.0
var _laser := 0.0
var _side := 1.0
var _since_hit := 99.0
## On a planet (stage 2): "fly", "landing" (settling onto its spot), "landed", "takeoff".
var state := "fly"
const LAND_TIME := 2.6
const GEAR := 3.6               # m: the hull's middle over the ground, landed (on its legs)
var _land_from := Transform3D.IDENTITY
var _land_to := Transform3D.IDENTITY
var _land_t := 0.0


func _ready() -> void:
	name = "Ship"
	add_to_group("cam_solid")   # (on foot, the camera stops short of the hull)
	set_meta("cam_reach", 60.0)
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if not control:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		stick += event.relative * Vector2(1.0, 1.0) / 260.0
		if stick.length() > 1.0:
			stick = stick.normalized()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		stick = Vector2.ZERO
	elif event is InputEventKey and event.pressed and not event.echo and state == "fly":
		match event.physical_keycode:
			KEY_J:
				toggle_cruise()
			KEY_X:
				throttle = 0.0
			KEY_C:
				stick = Vector2.ZERO
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_Y:
				toggle_cruise()
			JOY_BUTTON_B:
				throttle = 0.0


## The ship's numbers from your real fittings (the 2D game's): its class
## (Shipyard), the modules, tech and upgrades (PlayerData.mod) - as the 2D ship
## (Ship.apply_tech) - scaled to the 3D game's (the starting ship = MAX_HULL,
## MAX_SHIELD, MAX_SPEED); and its guns: the weapons on its hardpoints, each
## firing with its own damage, rate and colour (Hardpoints.stats).
var guns: Array = []            # [{id, kind, name, damage, interval, cool, color, ammo}]
var gun_on := 0                 # (the toolbar's pick: -1 all)
const DAMAGE_K := 1.6           # the 2D game's damage -> the 3D game's (its hulls are bigger)
const KIND_COLOR := {"pulse_cannon": Color(0.45, 0.9, 1.0), "plasma_cannon": Color(0.5, 1.0, 0.45), "missile_launcher": Color(1.0, 0.6, 0.25),
	"beam_emitter": Color(1.0, 0.3, 0.3), "electro": Color(0.65, 0.55, 1.0), "bouncer": Color(1.0, 0.85, 0.35)}


func apply_upgrades() -> void:
	var data: Node = CosmosGame.data
	if data == null:
		return
	var base := Shipyard.stats("player")
	var cls := Shipyard.stats(str(data.ship_class))
	max_hull = MAX_HULL * (float(cls["hull"]) + data.mod("max_hull")) / float(base["hull"])
	max_shield = MAX_SHIELD * (float(cls["shields"]) + data.mod("max_shields")) * maxf(0.1, 1.0 + data.mod("max_shields_mult")) / float(base["shields"])
	speed_k = float(cls["speed"]) * (1.0 + data.mod("speed_mult")) / float(base["speed"])
	shield = minf(shield, max_shield)
	hull = minf(hull, max_hull)
	guns.clear()
	for id in data.weapons:
		if str(id) == "":
			continue
		var w := Hardpoints.stats(str(id))
		var kind := Hardpoints.kind(str(id))
		guns.append({"id": id, "kind": kind, "name": Hardpoints.title(str(id)), "damage": float(w["damage"]) * DAMAGE_K * (float(w["interval"]) if w.get("style", "") == "beam" else 1.0),
			"interval": maxf(float(w.get("interval", 0.3)), 0.08), "cool": 0.0, "color": KIND_COLOR.get(kind, Color(0.45, 0.9, 1.0)),
			"ammo": "missile" if kind == "missile_launcher" else ""})
	if guns.is_empty():
		guns.append({"id": "", "kind": "pulse_cannon", "name": "Pulse lasers", "damage": LASER_DAMAGE, "interval": LASER_EVERY, "cool": 0.0, "color": KIND_COLOR["pulse_cannon"], "ammo": ""})
	laser_damage = guns[0]["damage"]


## Every gun ready (or the toolbar's pick) fires at what the sights are on -
## missiles take one from the hold each.
func _fire_guns(delta: float) -> void:
	var at: Vector3 = cosmos.ship_aim()
	for i in guns.size():
		var g: Dictionary = guns[i]
		g["cool"] = float(g["cool"]) - delta
		if g["cool"] > 0.0 or (gun_on >= 0 and gun_on < guns.size() and i != gun_on):
			continue
		if g["ammo"] != "" and not CosmosGame.data.remove_item(str(g["ammo"]), 1):
			continue
		g["cool"] = g["interval"]
		_side = -_side
		var muzzle := global_position + global_basis.x * 17.0 * _side - global_basis.z * 8.0
		var b := CosmosBolt.fire(cosmos, muzzle, at - muzzle, "player", float(g["damage"]), true)
		b.tint = g["color"]


func up() -> Vector3:
	return global_basis.y


func hurt(dmg: float, _from: Variant = null) -> void:
	if state != "fly":
		return
	_since_hit = 0.0
	var sh := minf(shield, dmg)
	shield -= sh
	hull -= dmg - sh
	if cosmos and cosmos.hud:
		cosmos.hud.hit_flash = 0.4
	if cruise != 0:
		_drop_cruise(MAX_SPEED)   # (hit: knocked out of the Hyperion drive)
	if hull <= 0.0 and cosmos:
		cosmos.ship_lost()


## The star's heat: shields first, then the hull (no knock out of the drive).
var heat := 0.0                 # 0 .. 1 (the HUD's)


func burn(dmg: float) -> void:
	if state != "fly" or dmg <= 0.0:
		return
	_since_hit = 0.0
	var sh := minf(shield, dmg)
	shield -= sh
	hull -= dmg - sh
	if hull <= 0.0 and cosmos:
		cosmos.ship_lost()


func toggle_cruise() -> void:
	if cruise == 0:
		cruise = 1
		cruise_t = 0.0
	else:
		_drop_cruise(MAX_SPEED)


func _drop_cruise(speed: float) -> void:
	cruise = 0
	velocity = velocity.normalized() * minf(velocity.length(), speed) if velocity.length() > 0.0 else Vector3.ZERO


## Sets down on `spot` (its basis: level with the ground; its origin GEAR over it).
func land_at(spot: Transform3D) -> void:
	state = "landing"
	_land_from = global_transform
	_land_to = spot
	_land_t = 0.0
	velocity = Vector3.ZERO
	cruise = 0
	throttle = 0.0
	stick = Vector2.ZERO
	_ang = Vector3.ZERO


func take_off() -> void:
	if state == "landed":
		state = "takeoff"
		_land_t = 0.0
		set_legs(false)


func _ground_states(delta: float) -> void:
	match state:
		"landing":
			_land_t += delta / LAND_TIME
			var k := smoothstep(0.0, 1.0, minf(_land_t, 1.0))
			global_transform = _land_from.interpolate_with(_land_to, k)
			if _land_t >= 1.0:
				global_transform = _land_to
				state = "landed"
				set_legs(true)
		"takeoff":
			_land_t += delta
			var u := _land_to.basis.y
			velocity = u * minf(4.0 + _land_t * 14.0, 26.0)
			global_position += velocity * delta
			if _land_t >= 1.6:
				state = "fly"
				throttle = 0.3
	_engines(delta)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if state != "fly":
		_ground_states(delta)
		return
	_read_input(delta)
	_since_hit += delta
	if _since_hit > 3.0:
		shield = minf(max_shield, shield + 12.0 * delta)
	if (trigger or bool(drive.get("fire", false))) and cruise == 0 and cosmos:
		_fire_guns(delta)
	var s := stick
	if s.length() < DEADZONE:
		s = Vector2.ZERO
	var want := Vector3(-s.y * RATES.x, -s.x * RATES.y, -roll * RATES.z)
	if cruise == 2:
		want *= 0.6
	_ang = _ang.lerp(want, 1.0 - exp(-delta * 6.0))
	basis = (basis * Basis.from_euler(_ang * delta)).orthonormalized()
	var tgt: Node3D = cosmos.target if cosmos and is_instance_valid(cosmos.target) and cosmos.target != self else null
	if cruise > 0 and tgt and s == Vector2.ZERO and absf(roll) < 0.1:
		# (the drive's assist: the nose comes round to the target)
		var to := (tgt.global_position - global_position).normalized()
		if cosmos:
			to = cosmos.steer(global_position, to, tgt)
		_aim = to
		var f := -basis.z
		var ang := f.angle_to(to)
		if ang > 0.0005:
			basis = (Basis(f.cross(to).normalized(), minf(ang, ASSIST * delta)) * basis).orthonormalized()
	var fwd := -basis.z
	var clear: float = (cosmos.clearance(global_position, null, velocity.normalized() if velocity.length() > 1.0 else -basis.z) if cruise > 0 else cosmos.clearance(global_position)) if cosmos else 1e9
	var target: Vector3
	var accel := ACCEL
	if cruise == 1:
		cruise_t += delta
		target = fwd * MAX_SPEED * maxf(throttle, 0.5)
		var aligned := tgt == null or fwd.angle_to(_aim if _aim != Vector3.ZERO else tgt.global_position - global_position) < ALIGN
		if cruise_t >= CRUISE_CHARGE and aligned:
			if cosmos and cosmos.clearance(global_position, tgt, fwd) < CRUISE_DROP * 1.2:
				cruise = 0     # (too close to something ahead to engage)
				if cosmos:
					cosmos.hyper_dropped(null)
			else:
				cruise = 2
	if cruise == 2:
		var cap := clear * CRUISE_SHARE
		var arrived := false
		if tgt:
			var left: float = cosmos.surface_distance(tgt, global_position)
			var other: float = cosmos.clearance(global_position, tgt, velocity.normalized() if velocity.length() > 1.0 else fwd)
			cap = minf(left * CRUISE_SHARE, other * 2.0)
			clear = other
			arrived = left < HYPER_ARRIVE
		if cosmos:
			well = cosmos.gravity(global_position)
			cap = minf(cap, CRUISE_MAX * float(well[0]))
		cap = clampf(cap, CRUISE_MIN, CRUISE_MAX)
		target = fwd * cap
		accel = maxf(cap * 1.5, 1200.0)
		if clear < CRUISE_DROP or arrived:
			_drop_cruise(MAX_SPEED * 1.4)
			target = fwd * MAX_SPEED * throttle
			if cosmos:
				cosmos.hyper_dropped(tgt if arrived else null)
	elif cruise == 0:
		var top := MAX_SPEED * speed_k * (BOOST if boosting else 1.0)
		target = fwd * top * throttle
		accel = ACCEL * (2.2 if boosting else 1.0)
	# (Faster than the cap - just out of cruise - bleeds off quickly.)
	if velocity.length() > target.length() + 50.0:
		accel = maxf(accel, velocity.length() * 1.5)
	velocity = velocity.move_toward(target, accel * delta)
	global_position += velocity * delta
	if cosmos:
		cosmos.bump(self)
	_engines(delta)


func _read_input(delta: float) -> void:
	if not drive.is_empty():
		throttle = float(drive.get("throttle", throttle))
		stick = drive.get("stick", stick)
		roll = float(drive.get("roll", 0.0))
		boosting = bool(drive.get("boost", false))
		return
	if not control:
		roll = 0.0
		boosting = false
		return
	var t := 0.0
	if Input.is_physical_key_pressed(KEY_W):
		t += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		t -= 1.0
	t += Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	throttle = clampf(throttle + t * delta * 0.7, -0.25, 1.0)
	roll = 0.0
	if Input.is_physical_key_pressed(KEY_A):
		roll -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		roll += 1.0
	roll += Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var joy := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if joy.length() > 0.15:
		stick = joy.limit_length(1.0)
	boosting = Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)


func speed() -> float:
	return velocity.length()


## The engines' glow and plumes follow the thrust.
func _engines(_delta: float) -> void:
	if _headless:
		return   # (no picture: and the dummy renderer can't hold instance parameters)
	var k := clampf(absf(throttle) * (1.6 if boosting else 1.0), 0.05, 1.6)
	if state == "landed":
		k = 0.0
	elif state == "landing" or state == "takeoff":
		k = 0.7
	elif cruise == 2:
		k = 2.2
	elif cruise == 1:
		k = 0.6 + cruise_t / CRUISE_CHARGE
	for g: MeshInstance3D in _glows:
		g.set_instance_shader_parameter("level", k)
	for h: Node3D in _plumes:
		h.scale = Vector3(1.0, 1.0, 0.3 + k * 1.4)
		(h.get_meta("mesh") as MeshInstance3D).set_instance_shader_parameter("level", k)


# --- The hull ------------------------------------------------------------------

var _hull: Node3D
var interior: CosmosShipInterior
var _legs: Array = []


func _build() -> void:
	_hull = Node3D.new()
	_hull.name = "Hull"
	_hull.scale = Vector3.ONE * SCALE
	add_child(_hull)
	var accent: Color = Galaxy.empire_color(Galaxy.HOME_EMPIRE)
	var white := CosmosStation._mat(Color(0.86, 0.87, 0.88), 0.35, 0.4)
	var dark := CosmosStation._mat(Color(0.18, 0.19, 0.22), 0.6, 0.45)
	var paint := CosmosStation._mat(accent.darkened(0.2), 0.3, 0.4)
	var glass := CosmosStation._mat(Color(0.05, 0.12, 0.2), 0.9, 0.08, Color(0.1, 0.4, 0.6) * 0.6)
	# Fuselage: sections along z (nose at -z), each [z, half width, half height, y].
	var sections := [[-9.5, 0.05, 0.05, 0.0], [-8.0, 0.7, 0.45, 0.0], [-5.5, 1.35, 0.85, 0.1], [-2.0, 1.8, 1.1, 0.2],
		[2.0, 2.0, 1.15, 0.2], [5.5, 1.8, 1.0, 0.1], [8.0, 1.4, 0.8, 0.0], [8.6, 1.1, 0.6, 0.0]]
	_add(_loft(sections, 12, false), white)
	# (inside the open tail: the hull's inner skin, so it isn't seen through)
	var skin := CosmosShipInterior._inner(Color(0.3, 0.31, 0.33), 0.7)
	skin.cull_mode = BaseMaterial3D.CULL_FRONT   # (its inside faces)
	_add(_loft(sections, 12, false), skin)
	_add(_loft([[-6.0, 0.9, 0.5, 0.95], [-4.0, 1.0, 0.7, 1.05], [-1.5, 0.85, 0.55, 1.05], [0.5, 0.4, 0.25, 0.95]], 10), glass)
	# A stripe of the empire's colour along the spine.
	_add(_loft([[-7.0, 0.25, 0.08, 0.6], [6.0, 0.3, 0.08, 1.2], [8.0, 0.2, 0.06, 0.85]], 6), paint)
	# Wings: swept, a little dihedral; a stripe on each.
	for s in [-1.0, 1.0]:
		_add(_wing(s, [Vector3(1.6, 0.0, -1.5), Vector3(1.6, 0.0, 5.5), Vector3(8.8, 0.55, 6.2), Vector3(8.4, 0.55, 3.6)], 0.28), white)
		_add(_wing(s, [Vector3(6.6, 0.48, 3.2), Vector3(6.6, 0.48, 6.0), Vector3(7.6, 0.55, 6.1), Vector3(7.6, 0.55, 3.4)], 0.32), paint)
		# Engines under the wing roots.
		var eng := [[1.5, 0.6, 0.6, 0.0], [3.0, 0.85, 0.85, 0.0], [8.4, 0.95, 0.95, 0.0], [9.4, 0.8, 0.8, 0.0]]
		var mi := _add(_loft(eng, 12), dark)
		mi.position = Vector3(2.9 * s, -0.55, 0.0)
		# Fins.
		_add(_wing(s, [Vector3(0.9, 0.9, 4.0), Vector3(0.9, 0.9, 8.2), Vector3(2.3, 3.0, 8.6), Vector3(2.0, 3.0, 7.2)], 0.18), paint)
		# Glow and plume at the nozzle.
		var g := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(3.2, 3.2)
		g.mesh = q
		g.material_override = _engine_mat(true)
		g.position = Vector3(2.9 * s, -0.55, 9.5)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hull.add_child(g)
		_glows.append(g)
		var c := CylinderMesh.new()
		c.top_radius = 0.75
		c.bottom_radius = 0.05
		c.height = 8.0
		c.radial_segments = 12
		c.rings = 1
		var holder := Node3D.new()
		holder.position = Vector3(2.9 * s, -0.55, 9.4)
		_hull.add_child(holder)
		var p := MeshInstance3D.new()
		p.mesh = c
		p.material_override = _engine_mat(false)
		p.rotation.x = -PI * 0.5
		p.position = Vector3(0, 0, 4.0)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(p)
		holder.set_meta("mesh", p)     # (the plume's instance parameter lives on the mesh)
		_plumes.append(holder)
	# Landing legs (out when landed) and the walkable inside (CosmosShipInterior).
	var leg_mat := CosmosStation._mat(Color(0.3, 0.31, 0.34), 0.7, 0.4)
	for at in [Vector3(0, 0, -11), Vector3(-6.5, 0, 9), Vector3(6.5, 0, 9)]:
		var leg := MeshInstance3D.new()
		leg.mesh = CosmosStation._cyl(0.45, 0.6, GEAR - 1.6, 8)
		leg.material_override = leg_mat
		leg.position = at + Vector3(0, -GEAR + (GEAR - 1.6) * 0.5, 0)
		add_child(leg)
		var foot := MeshInstance3D.new()
		foot.mesh = CosmosStation._box(Vector3(2.2, 0.3, 2.2))
		foot.material_override = leg_mat
		foot.position = at + Vector3(0, -GEAR + 0.15, 0)
		add_child(foot)
		_legs.append(leg)
		_legs.append(foot)
	interior = CosmosShipInterior.new()
	add_child(interior)
	interior.build(accent)
	set_legs(false)


## Legs and ramp down (landed) or up (flying).
func set_legs(down: bool) -> void:
	for l: Node3D in _legs:
		l.visible = down
	if interior:
		interior.set_ramp(down)


func _engine_mat(glow: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/cosmos/engine.gdshader")
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("tint", Color(0.45, 0.75, 1.0))
	return m


func _add(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	(_hull if _hull else self).add_child(mi)
	return mi


## A closed loft through elliptical sections [z, half width, half height, y].
static func _loft(sections: Array, seg: int, cap_end := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for s in sections:
		var ring := []
		for i in seg:
			var a := TAU * i / seg
			ring.append(Vector3(cos(a) * s[1], sin(a) * s[2] + s[3], s[0]))
		rings.append(ring)
	for r in rings.size() - 1:
		for i in seg:
			var j := (i + 1) % seg
			var a: Vector3 = rings[r][i]
			var b: Vector3 = rings[r][j]
			var c: Vector3 = rings[r + 1][j]
			var d: Vector3 = rings[r + 1][i]
			for v in [a, c, b, a, d, c]:
				st.add_vertex(v)
	# Caps (the tail's left open: a door in it - CosmosShipInterior).
	for e in ([[0, true], [rings.size() - 1, false]] if cap_end else [[0, true]]):
		var ring: Array = rings[e[0]]
		var mid := Vector3.ZERO
		for v in ring:
			mid += v
		mid /= ring.size()
		for i in seg:
			var j := (i + 1) % seg
			if e[1]:
				for v in [mid, ring[i], ring[j]]:
					st.add_vertex(v)
			else:
				for v in [mid, ring[j], ring[i]]:
					st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## A flat wing panel (four points of its top, mirrored by side), `t` thick.
static func _wing(side: float, pts: Array, t: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := []
	var bot := []
	for p: Vector3 in pts:
		top.append(Vector3(p.x * side, p.y + t * 0.5, p.z))
		bot.append(Vector3(p.x * side, p.y - t * 0.5, p.z))
	var faces := [[top[0], top[1], top[2]], [top[0], top[2], top[3]], [bot[0], bot[2], bot[1]], [bot[0], bot[3], bot[2]]]
	for i in 4:
		var j := (i + 1) % 4
		faces.append([top[i], bot[i], bot[j]])
		faces.append([top[i], bot[j], top[j]])
	var mid := Vector3.ZERO
	for v in top + bot:
		mid += v
	mid /= 8.0
	for f in faces:
		# (Godot's front faces wind clockwise: their normal is (p2 - p0) x (p1 - p0).)
		var n: Vector3 = (f[2] - f[0]).cross(f[1] - f[0])
		var k := faces.find(f)
		var out: Vector3 = Vector3.UP if k < 2 else (Vector3.DOWN if k < 4 else (f[0] + f[1] + f[2]) / 3.0 - mid)
		var order: Array = f if n.dot(out) >= 0.0 else [f[0], f[2], f[1]]
		for v in order:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()
