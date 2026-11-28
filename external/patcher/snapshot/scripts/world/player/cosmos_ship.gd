class_name CosmosShip
extends Node3D
## Your ship in the 3D game (Cosmos): a procedural hull (a lofted fuselage,
## swept wings, twin engines, a canopy, fins - in your empire's colours) and
## its flight: the mouse is a virtual stick (its offset from the middle sets
## the pitch and yaw rates; C or the middle button centres it), A / D roll,
## W / S the throttle (it stays where you leave it, stops at zero on the way
## through - S on into reverse thrust, a negative throttle; X stops), Shift
## boosts; thrusters: R / F (or Space / Ctrl) up and down, Q / E sideways
## (landing on pads).
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
const THRUST := 45.0            # m/s: the manoeuvring thrusters' (up / down, sideways)
const HULL_R := 24.0            # m (bumps): the hull ~58 m long (MinoanShip)

var velocity := Vector3.ZERO
var throttle := 0.0             # -REVERSE .. 1 (negative: thrust backward)
const REVERSE := 0.25
var stick := Vector2.ZERO       # x right, y down (mouse); |stick| <= 1
var roll := 0.0
var boosting := false
var lift := 0.0                 # -1 .. 1: the thrusters, up / down
var strafe := 0.0               # -1 .. 1: right / left
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
const GEAR := 4.4               # m: the hull's middle over the ground, landed (on its legs)
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
	if event is InputEventMouseMotion and (cosmos.mouse_steers() if cosmos else Input.mouse_mode == Input.MOUSE_MODE_CAPTURED) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		stick += event.relative * Vector2(1.0, 1.0) / 260.0
		if stick.length() > 1.0:
			stick = stick.normalized()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		stick = Vector2.ZERO
	elif event is InputEventKey and event.pressed and not event.echo and state == "fly":
		if Keybinds.pressed(event, "hyperion"):
			toggle_cruise()
		elif Keybinds.pressed(event, "stop"):
			throttle = 0.0
		elif Keybinds.pressed(event, "centre"):
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
		if CosmosGame.data.weapons_off.has(str(g.get("kind", ""))):   # (switched off on the toolbar)
			continue
		if g["ammo"] != "" and not CosmosGame.data.remove_item(str(g["ammo"]), 1):
			continue
		g["cool"] = g["interval"]
		_side = -_side
		var muzzle := global_position + global_basis.x * 17.0 * _side - global_basis.z * 8.0
		var b := CosmosBolt.fire(cosmos, muzzle, at - muzzle, "player", float(g["damage"]), true)
		b.velocity = (at - muzzle).normalized() * CosmosBolt.PULSE_SPEED + velocity   # (fast, and carried on your own speed)
		b.life = CosmosBolt.PULSE_LIFE
		b.slack = CosmosBolt.PULSE_SLACK
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
		if cosmos and cosmos.mining and cosmos.mining.active:
			cosmos.mining.step(delta, false)   # (the beam off)
		_ground_states(delta)
		return
	_read_input(delta)
	_since_hit += delta
	if _since_hit > 3.0:
		shield = minf(max_shield, shield + 12.0 * delta)
	var firing := (trigger or bool(drive.get("fire", false))) and cruise == 0
	var mining: CosmosMining = cosmos.mining if cosmos else null
	if mining:
		mining.cool(delta)
	if mining and mining.step(delta, firing):
		pass   # (the beam on a rock: the guns hold their fire)
	elif firing and cosmos:
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
		target = fwd * top * throttle + basis.y * lift * THRUST + basis.x * strafe * THRUST
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
		lift = float(drive.get("lift", 0.0))
		strafe = float(drive.get("strafe", 0.0))
		return
	if not control:
		roll = 0.0
		boosting = false
		lift = 0.0
		strafe = 0.0
		return
	var t := 0.0
	if Input.is_action_pressed("forward"):
		t += 1.0
	if Input.is_action_pressed("back"):
		t -= 1.0
	t += Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	_set_throttle(t, delta)
	roll = 0.0
	if Input.is_action_pressed("left"):
		roll -= 1.0
	if Input.is_action_pressed("right"):
		roll += 1.0
	roll += Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var joy := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if joy.length() > 0.15:
		stick = joy.limit_length(1.0)
	boosting = Input.is_action_pressed("boost")   # (the controls: Keybinds - Settings > Controls)
	lift = float(Input.is_action_pressed("up")) - float(Input.is_action_pressed("down"))
	strafe = float(Input.is_action_pressed("use")) - float(Input.is_action_pressed("strafe_left"))


## W / S move the throttle; it stops at zero on the way through (a detent:
## let go and press again to go on into reverse, or back to ahead), and a
## nudge left near zero snaps to it - stopping is one press, not a balancing act.
var _detent := false
const SNAP := 0.06


func _set_throttle(t: float, delta: float) -> void:
	if absf(t) < 0.05:
		_detent = false
		if absf(throttle) < SNAP:
			throttle = 0.0
		return
	if _detent:
		return
	var was := throttle
	throttle = clampf(throttle + t * delta * 0.7, -REVERSE, 1.0)
	if (was > 0.0 and throttle <= 0.0) or (was < 0.0 and throttle >= 0.0):
		throttle = 0.0
		_detent = true


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
	add_child(_hull)
	_accent = Galaxy.empire_color(Galaxy.HOME_EMPIRE)
	# The hull: a Minoan armoured hauler (MinoanShip - one mesh, its windows apart) - made on a
	# worker; till it's in, a plain stand-in its size (never waited for: the game comes in at once).
	if hull_ready():
		_body()
	else:
		var box := BoxMesh.new()
		box.size = Vector3(11.0, 7.0, 52.0)
		_stand_in = _add(box, EmpireKit.mat("hull"))
		_stand_in.name = "StandIn"
	for nc: Vector2 in MinoanShip.NACELLES:
		# Glow and plume at each nozzle.
		var g := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * MinoanShip.NACELLE_R * 2.4
		g.mesh = q
		g.material_override = _engine_mat(true)
		g.position = Vector3(nc.x, nc.y, MinoanShip.NOZZLE_Z - 0.2)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hull.add_child(g)
		_glows.append(g)
		var c := CylinderMesh.new()
		c.top_radius = MinoanShip.NACELLE_R * 0.75
		c.bottom_radius = 0.1
		c.height = 16.0
		c.radial_segments = 12
		c.rings = 1
		var holder := Node3D.new()
		holder.position = Vector3(nc.x, nc.y, MinoanShip.NOZZLE_Z - 0.3)
		_hull.add_child(holder)
		var p := MeshInstance3D.new()
		p.mesh = c
		p.material_override = _engine_mat(false)
		p.rotation.x = -PI * 0.5
		p.position = Vector3(0, 0, 8.0)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(p)
		holder.set_meta("mesh", p)     # (the plume's instance parameter lives on the mesh)
		_plumes.append(holder)
	# Landing legs (out when landed) and the walkable inside (CosmosShipInterior).
	var leg_mat := CosmosStation._mat(Color(0.3, 0.31, 0.34), 0.7, 0.4)
	for at in [Vector3(0, 0, -18), Vector3(-5.5, 0, 13), Vector3(5.5, 0, 13)]:
		var leg := MeshInstance3D.new()
		leg.mesh = CosmosStation._cyl(0.45, 0.6, GEAR - 2.6, 8)
		leg.material_override = leg_mat
		leg.position = at + Vector3(0, -GEAR + (GEAR - 2.6) * 0.5, 0)
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
	if CosmosShipInterior.dress_ready():
		interior.build(_accent)
	set_legs(false)


var _accent := Color.WHITE
var _stand_in: MeshInstance3D = null


## The hull's real mesh (its arrays made on a worker).
func _body() -> void:
	var ms := MinoanShip.meshes()
	_add(ms[0], EmpireKit.mat("hull")).name = "Body"
	var gm := _add(ms[1], EmpireKit.glass())
	gm.name = "Windows"
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _stand_in:
		_stand_in.queue_free()
		_stand_in = null


## (Each frame till they're in) The hull and the rooms put in as their workers finish -
## or now, waited for (`now`: you're boarding, a save resumed aboard).
func parts_in(now := false) -> bool:
	start_hull(true)   # (not started yet - no ship till now: soon, then)
	CosmosShipInterior.start_dress(true)
	if _stand_in and (now or hull_ready()):
		_body()
	if interior and not interior.built and (now or CosmosShipInterior.dress_ready()):
		interior.build(_accent)
	return _stand_in == null and interior != null and interior.built


## The hull's mesh data (MinoanShip.build), made once a run - on a worker from
## the title (CosmosWarm starts it), else here.
static var _arrays := {}
static var _arrays_task := -1


static func start_hull(soon := false) -> void:
	if _arrays.is_empty() and _arrays_task < 0:
		_arrays_task = Jobs.add(func(): _arrays = MinoanShip.build(), soon, "ship hull")   # (soon: your ship's here - not behind the low-priority queue)


static func hull_ready() -> bool:
	return not _arrays.is_empty() or (_arrays_task >= 0 and Jobs.done(_arrays_task))


## Its build collected if it was started (leaving the game: no task left in the pool).
static func finish_tasks() -> void:
	if _arrays_task >= 0:
		Jobs.wait(_arrays_task)
		_arrays_task = -1


static func hull_arrays() -> Dictionary:
	start_hull()
	if _arrays_task >= 0:
		Jobs.wait(_arrays_task)
		_arrays_task = -1
	return _arrays


## Legs and ramp down (landed) or up (flying).
func set_legs(down: bool) -> void:
	for l: Node3D in _legs:
		l.visible = down
	if interior:
		interior.set_ramp(down)


## The doorway through the tail (ship space) while the door's open - its hull's solid
## (CosmosHullGrid) cut there, as the inside's door is; else none.
func door_box() -> AABB:
	if interior == null or interior.door_t < 0.3:
		return AABB()
	var lo := Vector3(-MinoanShip.DOOR[0], CosmosShipInterior.FLOOR - 0.4, float(CosmosShipInterior.RAMP[1]) - 1.5)
	var hi := Vector3(MinoanShip.DOOR[0], float(MinoanShip.DOOR[2]) + 0.25, float(CosmosShipInterior.RAMP[1]) + 40.0)
	return AABB(lo, hi - lo)


func _engine_mat(glow: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/world/engine.gdshader")
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("tint", Color(0.45, 0.75, 1.0))
	return m


func _add(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	(_hull if _hull else self).add_child(mi)
	return mi
