class_name Cosmos
extends Node3D
## The 3D game (stage 1 of turning the whole game 3D: space). A star system
## of the galaxy (Galaxy's - the 2D game's systems, planets, stations and
## gates, at PlanetShape.PX_TO_M metres a map unit) built in 3D: its star,
## planets and moons of real procedural ground (CosmosPlanet: seen from
## orbit and flown down to, the same terrain), gas giants and their rings,
## stations, gates, asteroid fields, a sky of stars and nebulae - and your
## ship, flown from a third-person camera (CosmosShip, CosmosCam, CosmosHud).
## Fly through a gate: the next system is built the same way.
##
## Floating origin: the ship is kept near the world's origin (everything is
## moved back by its offset when it strays SHIFT_AT away) - float precision
## stays fine at any distance from the star. The scene builds itself a piece
## a frame under the loading veil (build_settled: every planet's first
## patches in); the planets refine their ground at LOD_HZ.
##   LoadVeil.change_to(Cosmos.SCENE, "3D space")

const SCENE := "res://scenes/cosmos.tscn"
const SHIFT_AT := 2500.0
const LOD_HZ := 30.0
const LOD_SLOW_HZ := 8.0
const NOISE_SIZE := 64
const SKY := preload("res://shaders/cosmos/sky.gdshader")

## The system you came from (arriving through its gate), "" at a start.
static var arrive_from := ""

var system_id := ""
var world: Node3D
var ship: CosmosShip
var cam: CosmosCam
var hud: CosmosHud
var light: DirectionalLight3D
var star: CosmosStar
var planets: Array = []         # CosmosPlanet
var stations: Array = []        # CosmosStation
var gates: Array = []           # CosmosGate
var fields: Array = []          # CosmosRocks
var target: Node3D = null
var noise: Texture3D
var built := false
var origin := Vector3.ZERO      # (how far the world has been moved back: system frame = world + origin)
var _lod_t := 0.0
var _gate_side := {}
var _menu: Control
var _terminal: Control
var _env: Environment
var _shells_on := true
const AMBIENT_OUT := Color(0.11, 0.12, 0.15)
const AMBIENT_IN := Color(0.42, 0.43, 0.46)    # (inside the ship: its lights all round)
var _jumping := false
var docked := false              # (stage 4: in a station's hangar)
var hangar: CosmosHangar = null
var dock_station: CosmosStation = null
var _dock := {}                  # the docking or undocking under way: {phase, t, from, to}
const DOCK_REACH := 2500.0       # F works this close to a station's ring
var jumped_to := ""
## Life on the planet you're on (stage 3): its animals and its pirates round you.
var creatures: Array = []       # CosmosCreature
var npcs: Array = []            # CosmosNpc
var kills := 0
var _life_t := 0.0
var _camps := {}                # CosmosPlanet -> [[planet-local position, Node3D props or null, pirates out]]
var _fauna := {}                # CosmosPlanet -> species (CosmosFauna.design)
var _life_rng := RandomNumberGenerator.new()
const LIFE_NEAR := 70.0         # animals appear this far away and further...
const LIFE_FAR := 170.0
const LIFE_GONE := 300.0        # ...and are gone beyond this
const CAMP_NEAR := 450.0        # a pirate camp's guards turn out within this
const LIFE_CAP := {"ocean": 10, "ice": 6, "volcanic": 6, "moon": 3}
## Traffic (stage 4): the other ships about you - traders, patrols, pirates.
var npc_ships: Array = []       # CosmosNpcShip
var bounty := 0
var _traffic_t := 0.0
var _pirate_cd := 45.0
const TRAFFIC_NEAR := 3500.0
const TRAFFIC_FAR := 14000.0
const TRAFFIC_GONE := 45000.0
## On foot (stage 2): the walker, while you're out of the ship.
var walker: CosmosWalker = null
const BOARD_REACH := 11.0
var dry_run := false             # (tests: a jump only noted, no scene change)


func _ready() -> void:
	if Galaxy.systems.is_empty():
		Galaxy._new_game_begin(true, false)   # (the scene run on its own: a galaxy for it)
	CosmosGame.ensure()
	system_id = Galaxy.current_system if Galaxy.systems.has(Galaxy.current_system) else Galaxy.HOME
	process_mode = Node.PROCESS_MODE_ALWAYS   # (Esc works while paused; the world below stops)
	world = Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	_build()


func get_save_data() -> Dictionary:
	return {}


## Built and every planet's first patches in (the loading veil waits for it).
func build_settled() -> bool:
	if not built:
		return false
	for p: CosmosPlanet in planets:
		if not p.settled():
			return false
	return true


func _stage() -> void:
	await get_tree().process_frame


func _build() -> void:
	noise = await _make_noise()
	_environment()
	await _stage()
	star = CosmosStar.new()
	star.setup(system_id, noise)
	world.add_child(star)
	await _stage()
	var recs := planet_records(system_id)
	var where := {}
	for r: Dictionary in recs:
		var p := CosmosPlanet.new()
		p.setup(r, noise)
		var at := _orbit_pos(r, where)
		where[r["id"]] = at
		p.position = at
		world.add_child(p)
		p.set_sun((star.global_position - p.global_position).normalized())
		planets.append(p)
		await _stage()
	var sys: Dictionary = Galaxy.system(system_id)
	for sid in sys.get("stations", []):
		var st: Dictionary = Galaxy.stations.get(sid, {})
		if st.is_empty():
			continue
		var s := CosmosStation.new()
		s.setup(st)
		world.add_child(s)
		s.position = _clear_of_planets(_map3(st["pos"], hash(sid)), s.reach + 1500.0)
		stations.append(s)
	await _stage()
	var gd: Dictionary = sys.get("gates", {})
	for to in gd:
		var g := CosmosGate.new()
		g.setup(str(to), noise)
		world.add_child(g)
		g.position = _map3(gd[to], hash(str(to)))
		g.look_at(Vector3.ZERO, Vector3.UP)
		gates.append(g)
	var i := 0
	for f in sys.get("fields", []):
		var rocks := CosmosRocks.new()
		rocks.setup(hash(system_id) + i, noise)
		world.add_child(rocks)
		rocks.position = _clear_of_planets(_map3(f, i * 31), CosmosRocks.SPREAD * 1.5)
		fields.append(rocks)
		i += 1
	await _stage()
	ship = CosmosShip.new()
	ship.cosmos = self
	world.add_child(ship)
	ship.apply_upgrades()
	ship.hull = float(CosmosGame.extra.get("hull", ship.max_hull))
	ship.shield = float(CosmosGame.extra.get("shield", ship.max_shield))
	ship.apply_upgrades()
	_place_ship()
	cam = CosmosCam.new()
	cam.target = ship
	cam.cosmos = self
	cam.process_priority = 10
	world.add_child(cam)
	cam.current = true
	cam.follow(1.0)
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(layer)
	hud = CosmosHud.new()
	hud.cosmos = self
	hud.ship = ship
	hud.cam = cam
	hud.process_priority = 20
	layer.add_child(hud)
	_build_menu(layer)
	_build_game_hud()
	built = true
	_update_lod(true)
	if _may_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.flash("%s - %s" % [system_title(), "arrived through the gate" if arrive_from != "" else ("your game, continued" if CosmosGame.from_save else "a new game")])
	if arrive_from != "" and not dry_run and DisplayServer.get_name() != "headless":
		CosmosGame.save(self)


## The 3D noise every shader samples (64^3, tiling): made once a run on a
## worker (at the title screen by CosmosWarm, else here), then kept.
static var _noise: Texture3D
static var _noise_task := -1
static var _noise_imgs: Array = []


static func start_noise() -> void:
	if _noise != null or _noise_task != -1:
		return
	_noise_imgs = []
	var imgs := _noise_imgs
	_noise_task = WorkerThreadPool.add_task(func():
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 4.0 / NOISE_SIZE
		n.fractal_octaves = 3
		imgs.append_array(n.get_seamless_image_3d(NOISE_SIZE, NOISE_SIZE, NOISE_SIZE, false, 0.1)), true, "cosmos noise")


## The noise if it's made (finishing it off if its task is done), else null.
static func noise_ready() -> Texture3D:
	if _noise != null:
		return _noise
	if _noise_task == -1 or not WorkerThreadPool.is_task_completed(_noise_task):
		return null
	WorkerThreadPool.wait_for_task_completion(_noise_task)
	_noise_task = -1
	var data: Array[Image] = []
	for im: Image in _noise_imgs:
		if im.get_format() != Image.FORMAT_L8:
			im.convert(Image.FORMAT_L8)
		data.append(im)
	_noise_imgs = []
	var t := ImageTexture3D.new()
	t.create(Image.FORMAT_L8, NOISE_SIZE, NOISE_SIZE, NOISE_SIZE, false, data)
	_noise = t
	return t


func _make_noise() -> Texture3D:
	start_noise()
	while noise_ready() == null:
		await get_tree().process_frame
	return _noise


func _environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY
	sky_mat.set_shader_parameter("noise_tex", noise)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(system_id + ":sky")
	sky_mat.set_shader_parameter("seed", float(rng.randi() % 997))
	var tint: Color = Galaxy.empire_color(Galaxy.owner_of(system_id))
	sky_mat.set_shader_parameter("neb_a", tint.darkened(0.3))
	sky_mat.set_shader_parameter("neb_b", Color.from_hsv(fmod(tint.h + 0.5 + rng.randf() * 0.2, 1.0), 0.6, 0.6))
	sky_mat.set_shader_parameter("band_axis", Vector3(rng.randf_range(-0.4, 0.4), 1.0, rng.randf_range(-0.4, 0.4)))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.11, 0.12, 0.15)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# The cinematic look (the game's style since 2026-11-21: photoreal):
	# ACES tone mapping, bloom on the bright things (the star, engines, lava,
	# lights), a touch of contrast.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.tonemap_white = 8.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.5)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env
	light = DirectionalLight3D.new()
	light.name = "Sunlight"
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	light.directional_shadow_max_distance = 900.0
	light.shadow_blur = 1.0
	light.directional_shadow_split_1 = 0.04   # (the first split: the ship and what's round it, sharp)
	light.shadow_bias = 0.08
	light.shadow_normal_bias = 2.5
	add_child(light)


# --- The system's layout --------------------------------------------------------

## The planets and moons of `sid` (the home system's from main.gd's orbits).
static func planet_records(sid: String) -> Array:
	var sys: Dictionary = Galaxy.system(sid)
	var out: Array = []
	if not sys.get("planets", []).is_empty():
		for p in sys["planets"]:
			out.append(p)
		return out
	if sid == Galaxy.HOME:
		var types := {"inferno": "volcanic", "ocean": "ocean", "glacier": "ice", "barren": "moon", "ringed_giant": "gas_giant", "storm_giant": "gas_giant"}
		for o in load("res://scripts/main.gd").HOME_ORBITS:
			var pd: Dictionary = Planets.PLANETS.get(o[0], {})
			var tpl := str(pd.get("template", "barren"))
			out.append({"id": o[0], "name": pd.get("name", o[0]), "type": types.get(tpl, "moon"), "template": tpl,
				"variant": int(pd.get("variant", 0)), "size": o[3], "orbit": o[1], "phase": o[2],
				"seed": int(pd.get("seed", hash(o[0]) % 100000)), "moon_of": o[4]})
	return out


func _orbit_pos(r: Dictionary, where: Dictionary) -> Vector3:
	var orbit := float(r["orbit"])
	var moon := str(r.get("moon_of", "")) != ""
	var period := (240.0 if moon else 900.0 * pow(orbit / 3000.0, 1.5)) * OrbitBody.ORBIT_SLOWDOWN
	var a := float(r["phase"]) + Galaxy.time * TAU / period
	var flat := Vector2.from_angle(a) * orbit * PlanetShape.PX_TO_M
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(r["id"]) + ":incline")
	var tilt := rng.randf_range(-0.06, 0.06) if not moon else rng.randf_range(-0.3, 0.3)
	var p := Vector3(flat.x, flat.length() * sin(tilt) * sin(a + rng.randf() * TAU), flat.y)
	if moon:
		p += where.get(r["moon_of"], Vector3.ZERO)
	return p


## A 2D map position in 3D: on the system's plane, a little above or below it.
static func _map3(p: Vector2, seed: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return Vector3(p.x, 0.0, p.y) * PlanetShape.PX_TO_M + Vector3(0, rng.randf_range(-2500.0, 2500.0), 0)


func _clear_of_planets(p: Vector3, gap: float) -> Vector3:
	for pl: CosmosPlanet in planets:
		var d := p - pl.position
		var need := pl.radius + (pl.atmo_radius - pl.radius) + gap
		if d.length() < need:
			p = pl.position + (d.normalized() if d.length() > 1.0 else Vector3.UP) * need
	return p


static var _placed_from_save := false


func _place_ship() -> void:
	var at := Vector3(0, 0, 60000)
	var face := Vector3.ZERO
	var saved: Array = CosmosGame.state.get("ship", {}).get("position", [])
	if CosmosGame.from_save and not _placed_from_save and arrive_from == "" and saved.size() == 2:
		# (where the save left you - the 2D game's map units)
		_placed_from_save = true
		at = _clear_of_planets(Vector3(float(saved[0]), 0, float(saved[1])) * PlanetShape.PX_TO_M - origin, 1500.0)
		face = (stations[0].position if not stations.is_empty() else star.position)
		ship.position = at
		ship.look_at(face, Vector3.UP)
		_shift_origin(true)
		return
	for g: CosmosGate in gates:
		if g.to == arrive_from:
			var inward := -g.position.normalized()
			at = g.position + inward * 1400.0
			face = at + inward
	if face == Vector3.ZERO and not stations.is_empty():
		var s: CosmosStation = stations[0]
		# (beside it, the star to one side: the station lit, not a silhouette)
		var away := (s.position - star.position).normalized()
		var side := away.cross(Vector3.UP).normalized()
		at = s.position + (side * 0.8 + away * 0.6).normalized() * (s.reach + 2400.0) + Vector3(0, 300, 0)
		face = s.position
	ship.position = at
	ship.look_at(face if face != Vector3.ZERO else Vector3.ZERO, Vector3.UP)
	_shift_origin(true)


## Puts the ship `alt` metres over planet `i`'s ground on its day side
## (`tilt` turns from the sub-solar point), level, looking along the
## horizon - or `pitch` radians down (tests, screenshots).
func warp_to(i: int, alt: float, tilt := 0.6, pitch := 0.0, at_up := Vector3.ZERO) -> void:
	var pl: CosmosPlanet = planets[i]
	var up := pl.sun_dir.rotated(pl.sun_dir.cross(Vector3.UP).normalized(), tilt).normalized()
	if at_up != Vector3.ZERO:
		up = at_up
	var r := pl.radius + pl.ground_at(up) + alt
	var p := pl.global_position + up * r
	var fwd := up.cross(Vector3.UP).normalized()
	ship.global_position = p
	ship.look_at(p + fwd, up)
	ship.rotate_object_local(Vector3.RIGHT, -pitch)
	ship.velocity = Vector3.ZERO
	ship.cruise = 0
	ship.throttle = 0.0
	ship.state = "fly"
	ship.stick = Vector2.ZERO
	_shift_origin(true)
	cam.follow(1.0)
	cam._q = ship.global_basis.get_rotation_quaternion()


## A spot of dry, gentle ground on planet `i`'s day side (its up vector) -
## for warp_to (tests, screenshots, the tour); its sub-solar point if none.
func land_up(i: int) -> Vector3:
	var pl: CosmosPlanet = planets[i]
	var s := pl.sun_dir
	var a := s.cross(Vector3.UP).normalized()
	var b := s.cross(a)
	for k in 600:
		var ang := 0.25 + 0.0025 * k
		var u := s.rotated(a.rotated(s, k * 2.39996), ang).normalized()
		var h := pl.shape.height(u)
		if h > 3.0 and h < pl.shape.amp * 0.9:
			var t := u.cross(b).normalized()
			var ok := true
			for o in [t, -t, u.cross(t), -u.cross(t)]:
				if absf(pl.shape.height((u * pl.radius + o * 16.0).normalized()) - h) > 1.8:
					ok = false
			if ok:
				return u
	return s


# --- Each frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	if not built or get_tree().paused:
		return
	_shift_origin()
	# (the shadows' reach: short on foot - more detail, far fewer casters - longer flying)
	light.directional_shadow_max_distance = 140.0 if walker else (450.0 if planet_below(ship.global_position, 300.0) else 900.0)
	var mode := DirectionalLight3D.SHADOW_ORTHOGONAL if walker else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if light.directional_shadow_mode != mode:
		light.directional_shadow_mode = mode
	var ld := (focus().global_position - star.global_position).normalized()
	var inside_ship: bool = walker != null and walker.deck == ship.interior
	if inside_ship:
		ld = (-ship.global_basis.y + ship.global_basis.x * 0.2).normalized()   # (inside the ship: its ceiling's lights)
	elif docked and hangar:
		ld = (-hangar.global_basis.y + hangar.global_basis.x * 0.3 + hangar.global_basis.z * 0.2).normalized()   # (the hangar's lights: from overhead)
	# (on a planet's night side the sun is behind it: the light fades out)
	var day := 1.0
	var lp := life_planet() if walker or ship.state != "fly" else planet_below(ship.global_position, 3000.0)
	if lp and not docked and not inside_ship:
		var up := (focus().global_position - lp.global_position).normalized()
		day = smoothstep(-0.12, 0.12, up.dot(lp.sun_dir))
	light.light_energy = lerpf(0.04, 1.0, day) if not inside_ship else 0.9
	light.shadow_enabled = not inside_ship   # (the hull would shade it all)
	var shells_on := not inside_ship and not docked
	if shells_on != _shells_on:
		_shells_on = shells_on   # (inside: no atmosphere or clouds drawn through the ceiling)
		for p: CosmosPlanet in planets:
			for n in ["Atmosphere", "Clouds"]:
				var sh := p.get_node_or_null(n)
				if sh:
					sh.visible = shells_on
	if _env:
		var amb := AMBIENT_IN if inside_ship else AMBIENT_OUT
		if _env.ambient_light_color != amb:
			_env.ambient_light_color = amb
			_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if inside_ship else Environment.REFLECTION_SOURCE_SKY
	light.global_basis = Basis.looking_at(ld, Vector3.UP if absf(ld.y) < 0.98 else Vector3.RIGHT)
	_lod_t += delta
	# (the ground's refining: LOD_HZ moving fast, LOD_SLOW_HZ walking or slow -
	# a visit of the planet underfoot is ~1 ms of script: rarer, fewer long frames)
	var hz := LOD_HZ if ship.speed() > 60.0 and walker == null else LOD_SLOW_HZ
	_update_lod(_lod_t >= 1.0 / hz)
	if _lod_t >= 1.0 / hz:
		_lod_t = 0.0
	if target != null and not is_instance_valid(target):
		target = null
	_star_heat(delta)
	_check_gates()
	_ramp_crossing()
	_docking(delta)
	_life_t += delta
	if _life_t >= 0.5:
		_life_t = 0.0
		_life()
	_traffic_t += delta
	_pirate_cd -= delta
	if _traffic_t >= 1.0:
		_traffic_t = 0.0
		_traffic()


func _update_lod(visit: bool) -> void:
	CosmosPlanet.deadline_us = Time.get_ticks_usec() + CosmosPlanet.MESH_BUDGET_US
	var eye := cam.global_position if cam else ship.global_position
	for p: CosmosPlanet in planets:
		var local := eye - p.global_position
		# (a far planet stays as it is - a few coarse patches: only those near are visited)
		if visit and (local.length() < p.radius * 25.0 or not p.settled() or p.deepest_hint > 1):
			p.update_lod(local)
		else:
			p.collect_only()


## What the world centres on: you on foot, else the ship.
func focus() -> Node3D:
	return walker if walker else ship


## Where the ship (you) is in the system's own frame (the world's origin moves).
func system_position() -> Vector3:
	if docked and dock_station:
		return dock_station.global_position + origin
	return ship.global_position + origin


func _shift_origin(force := false) -> void:
	var off := focus().global_position
	if not force and off.length() < SHIFT_AT:
		return
	origin += off
	for c in world.get_children():
		(c as Node3D).position -= off


func _check_gates() -> void:
	if _jumping:
		return
	for g: CosmosGate in gates:
		var c := g.crossing(ship.global_position)
		var near := absf(c.x) < 300.0 and c.y < CosmosGate.RADIUS * 1.5
		var side := signf(c.x)
		if near and _gate_side.has(g) and _gate_side[g] != side and c.y < CosmosGate.RADIUS:
			jump(g.to)
			return
		if near:
			_gate_side[g] = side
		else:
			_gate_side.erase(g)


## Through the gate: the next system (built the same way, under the veil).
func jump(to: String) -> void:
	if _jumping or not Galaxy.systems.has(to):
		return
	_jumping = true
	jumped_to = to
	if dry_run:
		return
	arrive_from = system_id
	Galaxy.current_system = to
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	LoadVeil.change_to(SCENE, "Jumping to %s" % Galaxy.system(to).get("name", to))


# --- What the ship and the HUD ask ------------------------------------------------

## Metres from `p` to the nearest thing the Hyperion drive must slow for
## (`skip`: the target it's flying to, counted apart).
## `ahead`: only what lies ahead along it (the drive's way) - or very close - counts.
func clearance(p: Vector3, skip: Node3D = null, ahead := Vector3.ZERO) -> float:
	var best := INF
	if star and star != skip and _ahead(p, star.global_position, star.radius, ahead):
		best = p.distance_to(star.global_position) - star.radius * 1.3
	for pl: CosmosPlanet in planets:
		if pl == skip or not _ahead(p, pl.global_position, pl.radius, ahead):
			continue
		var d := pl.global_position.distance_to(p)
		if d < pl.radius * 3.0:
			d -= pl.radius + pl.ground_at(p - pl.global_position)
		else:
			d -= pl.radius
		if ahead != Vector3.ZERO:
			d -= CosmosShip.HYPER_ARRIVE - CosmosShip.CRUISE_DROP   # (the drive keeps clear of planets by more)
		best = minf(best, d)
	for s: CosmosStation in stations:
		if s != skip and _ahead(p, s.global_position, s.reach, ahead):
			best = minf(best, s.global_position.distance_to(p) - s.reach)
	for g: CosmosGate in gates:
		if g != skip and _ahead(p, g.global_position, CosmosGate.RADIUS, ahead):
			best = minf(best, g.global_position.distance_to(p) - CosmosGate.RADIUS)
	return best


## The way to fly from `p` toward `dir` (the target `skip`) round anything
## in between: a body ahead whose clearance zone the line would cross pushes
## the way out sideways (the Hyperion drive's assist).
func steer(p: Vector3, dir: Vector3, skip: Node3D) -> Vector3:
	var out := dir
	var obstacles: Array = []
	for s in stations:
		obstacles.append([s.global_position, (s as CosmosStation).reach + 900.0])
	for g in gates:
		obstacles.append([g.global_position, CosmosGate.RADIUS + 900.0])
	for pl: CosmosPlanet in planets:
		obstacles.append([pl.global_position, pl.radius + CosmosShip.HYPER_ARRIVE + 800.0, pl])
	for o in obstacles:
		if o.size() > 2 and o[2] == skip:
			continue
		var to: Vector3 = o[0] - p
		var along := to.dot(dir)
		if along <= 0.0 or along > float(o[1]) * 6.0:
			continue
		var side := to - dir * along
		var miss := side.length()
		if miss < float(o[1]):
			var away := -side.normalized() if miss > 1.0 else dir.cross(Vector3.UP).normalized()
			out += away * (float(o[1]) - miss) / maxf(along, 1.0) * 2.0
	return out.normalized()


## Whether a body at `at` (of radius r) is in the way along `dir` from `p`:
## within the cone its size makes ahead, or close enough to matter anyway.
func _ahead(p: Vector3, at: Vector3, r: float, dir: Vector3) -> bool:
	if dir == Vector3.ZERO:
		return true
	var to := at - p
	var d := to.length()
	if d - r < 600.0:
		return true
	return to.dot(dir) > 0.0 and (to - dir * to.dot(dir)).length() < r * 2.5 + 2000.0


## Metres from `p` to body `b`'s surface (a planet's ground, a station's reach...).
func surface_distance(b: Node3D, p: Vector3) -> float:
	var d := b.global_position.distance_to(p)
	if b is CosmosPlanet:
		return d - (b as CosmosPlanet).radius - maxf((b as CosmosPlanet).ground_at(p - b.global_position), 0.0)
	if b is CosmosStar:
		return d - (b as CosmosStar).radius * 1.3
	if b is CosmosStation:
		return d - (b as CosmosStation).reach
	if b is CosmosGate:
		return d - CosmosGate.RADIUS
	return d


## Gravity wells (the Hyperion drive): every body pulls the drive's top speed
## down within WELL x its radius - the deeper in, the slower (to 4% at its
## surface): [factor 0.04..1, the body pulling hardest or null].
const WELL := {"planet": 12.0, "moon": 8.0, "gas": 12.0, "star": 9.0}


func gravity(p: Vector3) -> Array:
	var best := 1.0
	var who: Node3D = null
	var bodies_: Array = planets.duplicate()
	if star:
		bodies_.append(star)
	for b: Node3D in bodies_:
		var r: float
		var w: float
		if b is CosmosStar:
			r = (b as CosmosStar).radius
			w = r * WELL["star"]
		else:
			var pl := b as CosmosPlanet
			r = pl.radius
			w = r * (WELL["gas"] if pl.shape.kind == "gas" else (WELL["moon"] if str(pl.rec.get("moon_of", "")) != "" else WELL["planet"]))
		var d := b.global_position.distance_to(p)
		if d >= w:
			continue
		var f := pow(clampf((d - r) / (w - r), 0.04, 1.0), 0.6)
		if f < best:
			best = f
			who = b
	return [best, who]


## The Hyperion drive dropped out: at its target, or for something in the way.
func hyper_dropped(at: Node3D) -> void:
	if hud == null:
		return
	if at:
		hud.flash("Arrived: %s" % label_of(at))
	else:
		hud.flash("Hyperion drive: dropped out - something close")


## Keeps the ship out of the ground, stations, rocks and the star.
func bump(s: CosmosShip) -> void:
	if s.state != "fly":
		return
	var p := s.global_position
	for pl: CosmosPlanet in planets:
		var local := p - pl.global_position
		var r := local.length()
		if r > pl.radius + pl.shape.top() + 50.0:
			continue
		var up := local / r
		var ground := pl.radius + pl.ground_at(local) + CosmosShip.HULL_R * 0.4
		if r < ground:
			s.global_position = pl.global_position + up * ground
			var vn := s.velocity.dot(up)
			if vn < 0.0:
				s.velocity -= up * vn
				s.velocity *= 0.985
			if s.cruise != 0:
				s.cruise = 0
	for st: CosmosStation in stations:
		_push(s, st.global_position, st.reach * 0.55)
	for f: CosmosRocks in fields:
		var lp := p - f.global_position
		if lp.length() > CosmosRocks.SPREAD * 2.5:
			continue
		for rk in f.rocks:
			_push(s, f.global_position + rk[0], rk[1] * 0.9 + CosmosShip.HULL_R * 0.6)
	if star:
		_push(s, star.global_position, star.radius * 1.12)


func _push(s: CosmosShip, at: Vector3, r: float) -> void:
	var d := s.global_position - at
	var l := d.length()
	if l >= r or l < 0.001:
		return
	var n := d / l
	s.global_position = at + n * r
	var vn := s.velocity.dot(n)
	if vn < 0.0:
		s.velocity -= n * vn * 1.4
	if s.cruise != 0:
		s.cruise = 0
		if hud:
			hud.flash("Collision - cruise drive off")


# --- The camera's clearance ----------------------------------------------------

## The camera's place on the line from `pivot` (what it looks at) to `want`,
## stopped short of anything solid in between - hulls, stations, a camp's
## crates, the hangar's walls (every lit part of the nodes in the "cam_solid"
## group, as boxes), tree trunks and big boulders, the ground. `skip`: the
## node the camera follows from outside (its own hull doesn't block it).
func camera_clear(pivot: Vector3, want: Vector3, skip: Node = null) -> Vector3:
	var seg := want - pivot
	var L := seg.length()
	if L < 0.01:
		return want
	var dir := seg / L
	var t := L
	for n in get_tree().get_nodes_in_group("cam_solid"):
		var n3 := n as Node3D
		if n3 == null or n3 == skip or not n3.is_visible_in_tree():
			continue
		var reach: float = float(n3.get_meta("cam_reach", 600.0))
		if n3.global_position.distance_to(pivot) > reach + L:
			continue
		if not n3.has_meta("cam_parts"):
			var parts: Array = []
			for mi in n3.find_children("*", "MeshInstance3D", true, false):
				if (mi as MeshInstance3D).material_override is StandardMaterial3D and mi.mesh:
					parts.append(mi)
			n3.set_meta("cam_parts", parts)
		for mi: MeshInstance3D in n3.get_meta("cam_parts"):
			if not is_instance_valid(mi) or not mi.is_visible_in_tree():
				continue
			var hit := _seg_box(mi, pivot, dir, t)
			if hit < t:
				t = hit
	# Trunks and boulders (vertical cylinders), and the ground, sampled along.
	var pl := planet_below(pivot, 80.0)
	if pl:
		var local0 := pivot - pl.global_position
		var rocks := pl.rocks_near(local0, L + 2.0)
		var steps := 10
		for i in range(1, steps + 1):
			var d := t * i / steps
			var p := pivot + dir * d
			var lp := p - pl.global_position
			var up := lp.normalized()
			if lp.length() < pl.radius + pl.ground_at(lp) + 0.35:
				t = maxf(d - t / steps, 0.0)
				break
			var blocked := false
			for rk in rocks:
				var c: Vector3 = rk[0]
				var v := lp - c
				var hgt := v.dot(up)
				if hgt > -0.5 and hgt < float(rk[2]) and (v - up * hgt).length() < float(rk[1]) + 0.25:
					blocked = true
					break
			if blocked:
				t = maxf(d - t / steps, 0.0)
				break
	if t >= L:
		return want
	return pivot + dir * maxf(t - 0.35, minf(0.6, L))


## Where the ray pivot + dir * s (s up to `limit`) enters a mesh's box, or INF.
static func _seg_box(mi: MeshInstance3D, o: Vector3, dir: Vector3, limit: float) -> float:
	var inv := mi.global_transform.affine_inverse()
	var lo := inv * o
	var ld := inv.basis * dir
	var box := mi.mesh.get_aabb()
	var t0 := 0.0
	var t1 := limit
	for a in 3:
		var bmin := box.position[a]
		var bmax := box.position[a] + box.size[a]
		if absf(ld[a]) < 1e-8:
			if lo[a] < bmin or lo[a] > bmax:
				return INF
			continue
		var ta := (bmin - lo[a]) / ld[a]
		var tb := (bmax - lo[a]) / ld[a]
		if ta > tb:
			var x := ta
			ta = tb
			tb = x
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return INF
	return t0 if t0 > 0.0 else INF


## `p` moved up to `m` metres over the ground if it's lower (the camera).
func keep_above_ground(p: Vector3, m: float) -> Vector3:
	if walker and walker.deck == ship.interior:
		var l := ship.interior.to_local(p)
		var c := ship.interior.confine(l, 0.25)
		c.y = clampf(l.y, ship.interior.floor_y(c) + 0.3, ship.interior.ceiling_y(c) - 0.2)
		return ship.interior.to_global(c)
	if docked and hangar:
		return hangar.to_global(CosmosHangar.inside(hangar.to_local(p), maxf(m, 0.8)))
	for pl: CosmosPlanet in planets:
		var local := p - pl.global_position
		var r := local.length()
		if r > pl.radius + pl.shape.top() + m + 10.0:
			continue
		var g := pl.radius + pl.ground_at(local) + m
		if r < g:
			return pl.global_position + local / r * g
	return p


func bodies() -> Array:
	var out: Array = [star]
	out.append_array(planets)
	out.append_array(stations)
	out.append_array(gates)
	if walker:
		out.append(ship)
	for x in npc_ships:
		if is_instance_valid(x) and not x.dead and x.global_position.distance_to(focus().global_position) < 20000.0:
			out.append(x)
	return out


func label_of(b: Node3D) -> String:
	if b is CosmosPlanet:
		return str(b.rec.get("name", "?"))
	if b is CosmosStation:
		return str(b.record.get("name", "Station"))
	if b is CosmosGate:
		return "Gate to %s" % Galaxy.system(b.to).get("name", b.to)
	if b is CosmosStar:
		return str(Galaxy.system(system_id).get("name", "Star"))
	if b is CosmosShip:
		return "Your ship"
	if b is CosmosNpcShip:
		return b.label
	return b.name


func radius_of(b: Node3D) -> float:
	if b is CosmosPlanet:
		return b.radius
	if b is CosmosStar:
		return b.radius
	if b is CosmosGate:
		return 0.0
	if b is CosmosStation:
		return b.reach * 0.5
	if b is CosmosNpcShip:
		return b.reach
	return 0.0


func system_title() -> String:
	var sys: Dictionary = Galaxy.system(system_id)
	return "%s system - %s" % [sys.get("name", system_id), Galaxy.empire_name(str(sys.get("owner", "")))]


## The nearest planet, and how high over its ground (the HUD's line).
func where_text() -> String:
	if walker and walker.deck == ship.interior:
		return "Aboard your ship" + ("" if ship.state == "landed" else " - in flight")
	if walker and walker.deck:
		return "In the hangar of %s" % label_of(dock_station)
	if walker:
		var t0: Dictionary = Planets.TYPES.get(str(walker.planet.rec.get("type", "")), {})
		return "On foot on %s (%s)%s" % [walker.planet.rec.get("name", ""), t0.get("label", "planet"), " - swimming" if walker.swimming else ""]
	var best: CosmosPlanet = null
	var bd := INF
	for pl: CosmosPlanet in planets:
		var d := pl.global_position.distance_to(ship.global_position) - pl.radius
		if d < bd:
			bd = d
			best = pl
	if best == null:
		return ""
	var t: Dictionary = Planets.TYPES.get(str(best.rec.get("type", "")), {})
	var kind := str(t.get("label", "planet"))
	if bd < best.radius * 0.6:
		var alt := ship.global_position.distance_to(best.global_position) - best.radius - best.ground_at(ship.global_position - best.global_position)
		return "Altitude %s over %s (%s)" % [CosmosHud._dist(alt), best.rec.get("name", ""), kind]
	return "Nearest: %s (%s) %s" % [best.rec.get("name", ""), kind, CosmosHud._dist(bd)]


## The body nearest the middle of the view.
func pick_target() -> void:
	var fwd := -cam.global_basis.z
	var best: Node3D = null
	var bd := 0.0
	for b: Node3D in bodies():
		var d := (b.global_position - cam.global_position).normalized().dot(fwd)
		if d > bd and b != target:
			bd = d
			best = b
	target = best


## Near the star: heat - from HEAT_FROM star radii in, rising to the surface -
## slowly burning the shields, then the hull (HEAT_DPS a second at its worst).
const HEAT_FROM := 5.0
const HEAT_DPS := 40.0
var _heat_warned := false


func _star_heat(delta: float) -> void:
	if star == null or ship.state != "fly":
		ship.heat = 0.0
		return
	var d := ship.global_position.distance_to(star.global_position) - star.radius
	var k := clampf(1.0 - d / (star.radius * HEAT_FROM), 0.0, 1.0)
	ship.heat = k
	if k <= 0.0:
		_heat_warned = false
		return
	if not _heat_warned and k > 0.15:
		_heat_warned = true
		hud.flash("Hull heating - too close to the star")
	ship.burn(HEAT_DPS * k * k * delta)


# --- Landing, on foot (stage 2) ------------------------------------------------

## The planet the ship is low over, or null.
func planet_below(p: Vector3, within := 400.0) -> CosmosPlanet:
	for pl: CosmosPlanet in planets:
		if pl.shape.kind == "gas":
			continue
		var local := p - pl.global_position
		var r := local.length() - pl.radius
		if r - pl.shape.top() > within:
			continue   # (well above its highest ground: no need to sample it)
		if r - pl.ground_at(local) < within:
			return pl
	return null


## Whether the ship can set down here: "" if it can, else why not.
func landing_check() -> String:
	if ship.state != "fly":
		return "not flying"
	var pl := planet_below(ship.global_position, 160.0)
	if pl == null:
		return "too high: come within 160 m of the ground"
	if ship.speed() > 80.0:
		return "too fast: slow under 80 m/s"
	var local := ship.global_position - pl.global_position
	var u := local.normalized()
	var h := pl.shape.height(u)
	if pl.shape.sea == 1 and h < 0.6:
		return "water below - find dry land"
	if pl.shape.sea == 3 and h < 0.6:
		return "lava below"
	# Level enough: the ground round the spot within a few metres.
	var t1 := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := u.cross(t1)
	var lo := h
	var hi := h
	for o in [t1, -t1, t2, -t2]:
		var hh := pl.shape.height((u * pl.radius + o * 16.0).normalized())
		lo = minf(lo, hh)
		hi = maxf(hi, hh)
	if hi - lo > 4.0:
		return "too steep here"
	var fwd0 := -ship.global_basis.z
	fwd0 = (fwd0 - u * fwd0.dot(u)).normalized()
	if fwd0.length() > 0.5:
		var test_spot := Transform3D(Basis.looking_at(fwd0, u), pl.global_position + u * (pl.radius + h + CosmosShip.GEAR))
		var ry := ramp_ground(pl, test_spot)
		if ry < -CosmosShip.GEAR - 2.6 or ry > CosmosShipInterior.FLOOR - 0.25:
			return "the ground under the tail is too uneven for the ramp"
	for rk in pl.rocks_near(local.normalized() * pl.radius, 24.0):
		if float(rk[2]) > 1.0:
			return "trees or boulders in the way"
	return ""


## Where the ramp's foot meets the ground, for a ship set down at `spot`
## (ship-space height: the ramp's slope found by a few rounds - where it
## lands depends on how far it drops).
func ramp_ground(pl: CosmosPlanet, spot: Transform3D) -> float:
	var y := -CosmosShip.GEAR
	var inv := spot.affine_inverse()
	for i in 4:
		var drop := CosmosShipInterior.FLOOR - y
		var z := CosmosShipInterior.RAMP[1] + sqrt(maxf(pow(CosmosShipInterior.RAMP[2], 2.0) - drop * drop, 1.0))
		var w := spot * Vector3(0, y, z)
		var d := (w - pl.global_position).normalized()
		y = (inv * (pl.global_position + d * (pl.radius + pl.shape.surface(d)))).y
	return y


## Sets the ship down on the ground under it (L), level with the ground.
func land() -> bool:
	var why := landing_check()
	if why != "":
		hud.flash("Can't land: " + why)
		return false
	var pl := planet_below(ship.global_position, 160.0)
	var local := ship.global_position - pl.global_position
	var u := local.normalized()
	var ground := pl.radius + pl.shape.height(u) + CosmosShip.GEAR
	var fwd := -ship.global_basis.z
	fwd = (fwd - u * fwd.dot(u)).normalized()
	if fwd.length() < 0.5:
		fwd = u.cross(Vector3.RIGHT).normalized()
	var spot := Transform3D(Basis.looking_at(fwd, u), pl.global_position + u * ground)
	ship.land_at(spot)
	ship.interior.ramp_end_y = ramp_ground(pl, spot)
	hud.flash("Landing on %s" % pl.rec.get("name", ""))
	return true


## Up from the pilot's seat (E): you on your feet in the cockpit - landed,
## docked or in flight (the ship flies on as it was: its deck carries you).
## Out you go down the ramp (lowered when landed).
func get_out() -> void:
	if walker or not ship.interior:
		return
	walker = CosmosWalker.new()
	walker.cosmos = self
	walker.planet = planet_below(ship.global_position, 300.0)
	world.add_child(walker)
	walker.global_position = ship.interior.to_global(CosmosShipInterior.SEAT + Vector3(0, 0, 1.6))
	walker.set_deck(ship.interior)
	walker.heading = ship.global_basis.z
	walker.facing = ship.global_basis.z
	cam.walker = walker
	_gauge_on_walker(true)
	ship.control = false
	ship.trigger = false
	ship.stick = Vector2.ZERO
	ship.roll = 0.0
	ship.interior.stack_cargo(_cargo_units())
	if ship.state == "landed":
		hud.flash("Up from the seat - the ramp's down at the back of the hold" if not docked else "Up from the seat - down the ramp into the hangar")
	else:
		hud.flash("Up from the seat - the ship flies on. E at the seat: back to the controls")


## Straight out of the ship and down its ramp (the door and ramp opened at
## once): you standing just off the ramp's foot (tests, shots, the tour).
func disembark() -> void:
	if walker == null:
		get_out()
	var inside := ship.interior
	inside.set_ramp(true)
	inside.door_t = 1.0
	inside.ramp_t = 1.0
	inside._process(0.0)
	var foot := inside.ramp_foot() + Vector3(0, 0, 1.2)
	walker.global_position = inside.to_global(foot)
	if docked and hangar:
		walker.set_deck(hangar)
	else:
		walker.planet = planet_below(walker.global_position, 80.0)
		walker.set_deck(null)
		var l := walker.global_position - walker.planet.global_position
		walker.global_position = walker.planet.global_position + l.normalized() * (walker.planet.radius + walker.floor_at(l) + 0.05)


## Back aboard and in the pilot's seat at once (tests, shots, the tour).
func embark() -> bool:
	if walker == null:
		return false
	walker.global_position = ship.interior.to_global(CosmosShipInterior.SEAT + Vector3(0, 0, 0.5))
	walker.set_deck(ship.interior)
	return board()


func _cargo_units() -> int:
	var n := 0
	for c in Galaxy.COMMODITIES:
		n += CosmosGame.data.count(c)
	return n


## Back at the controls (E at the pilot's seat).
func board() -> bool:
	if walker == null:
		return false
	if walker.deck != ship.interior or not ship.interior.at_seat(ship.interior.to_local(walker.global_position)):
		hud.flash("The pilot's seat is in the cockpit, at the nose" if walker.deck == ship.interior else "Board up the ramp, under the ship's tail")
		return false
	walker.queue_free()
	walker = null
	_gauge_on_walker(false)
	cam.to_ship()
	ship.control = true
	_shift_origin(true)
	hud.flash("At the controls" + (" - L or Space: %s" % ("undock" if docked else "take off") if ship.state == "landed" else ""))
	return true


## Walking in and out by the ramp: off its foot onto the ground (or the
## hangar's deck), and onto it from there.
func _ramp_crossing() -> void:
	if walker == null or not ship.interior:
		return
	var inside := ship.interior
	var l := inside.to_local(walker.global_position)
	# (which way you're going decides it: off the ramp walking away, onto it walking in)
	var aft := walker.velocity.dot(ship.global_basis.z)
	if walker.deck == inside:
		if inside.ramp_down and l.z > inside.foot_z() - 0.2 and aft > 0.2:
			if docked and hangar:
				walker.set_deck(hangar)
			else:
				walker.planet = planet_below(walker.global_position, 50.0)
				walker.set_deck(null)
	elif inside.ramp_down and aft < -0.2 and absf(l.x) < CosmosShipInterior.RAMP[0] and l.z > inside.foot_z() - 0.9 and l.z < inside.foot_z() + 0.5 and absf(l.y - inside.ramp_end_y) < 0.8:
		walker.set_deck(inside)
		inside.stack_cargo(_cargo_units())


## Keeps the walker out of the landed ship and the boulders.
func walker_bumps(w: CosmosWalker) -> void:
	var u := w.up()
	if w.deck == ship.interior:
		return
	if (ship.state == "landed" or ship.state == "landing") and ship.interior:
		# (outside: the landing legs are solid; under the hull you walk free - to the ramp)
		for leg: Vector3 in [Vector3(0, 0, -11), Vector3(-6.5, 0, 9), Vector3(6.5, 0, 9)]:
			var d := w.global_position - ship.to_global(leg)
			d -= u * d.dot(u)
			if d.length() < 1.6 and d.length() > 0.01:
				w.global_position += d.normalized() * (1.6 - d.length())
	if w.deck:
		return
	var local := w.global_position - w.planet.global_position
	for rk in w.planet.rocks_near(local, 3.0):
		var c: Vector3 = rk[0]
		var d := local - c
		var flat := d - u * d.dot(u)
		var need: float = rk[1] + CosmosWalker.BODY_R
		# (low ones you step over; tall ones block)
		if float(rk[2]) > 0.5 and flat.length() < need and d.dot(u) < float(rk[2]) and flat.length() > 0.001:
			w.global_position += flat.normalized() * (need - flat.length())


# --- Life (stage 3) --------------------------------------------------------------

## The planet whose life is about you: on foot, landed, or flying low.
func life_planet() -> CosmosPlanet:
	if walker:
		return walker.planet
	if ship and ship.state != "fly":
		return planet_below(ship.global_position, 100.0)
	return planet_below(ship.global_position, 600.0) if ship else null


func fauna_of(pl: CosmosPlanet) -> Array:
	if not _fauna.has(pl):
		_fauna[pl] = CosmosFauna.design(pl.shape, int(pl.rec.get("seed", 1)), str(pl.rec.get("type", "rocky")))
	return _fauna[pl]


## A planet's pirate camps: a few, where its seed puts them, on dry and
## gentle ground.
func camps_of(pl: CosmosPlanet) -> Array:
	if _camps.has(pl):
		return _camps[pl]
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pl.rec.get("seed", 1)) * 13 + 5
	var want := rng.randi_range(3, 6)
	var tries := 0
	while out.size() < want and tries < 400:
		tries += 1
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var h := pl.shape.height(d)
		if pl.shape.sea > 0 and h < 2.0:
			continue
		var t := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		if absf(pl.shape.height((d * pl.radius + t * 12.0).normalized()) - h) > 3.0:
			continue
		out.append([d * (pl.radius + h), null, 0])
	_camps[pl] = out
	return out


func _life() -> void:
	creatures = creatures.filter(func(x): return is_instance_valid(x))
	npcs = npcs.filter(func(x): return is_instance_valid(x))
	var pl := life_planet()
	var f := focus()
	for list in [creatures, npcs]:
		for x in list:
			if pl == null or x.get("planet") != pl or x.global_position.distance_to(f.global_position) > LIFE_GONE * 1.3:
				x.queue_free()
	if pl == null or pl.shape.kind == "gas":
		return
	var here := f.global_position - pl.global_position
	# Animals.
	var kinds := fauna_of(pl)
	var cap: int = LIFE_CAP.get(str(pl.rec.get("type", "")), 4)
	var alive := 0
	for x: CosmosCreature in creatures:
		if is_instance_valid(x) and not x.dead and x.global_position.distance_to(f.global_position) < LIFE_GONE:
			alive += 1
	if alive < cap and not kinds.is_empty():
		var k: Dictionary = kinds[_life_rng.randi() % kinds.size()]
		if k["temper"] == "predator" and _life_rng.randf() < (0.6 if k["monster"] else 0.35):
			k = kinds[0]
		var u := here.normalized()
		var t := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized().rotated(u, _life_rng.randf() * TAU)
		var at := (here + t * _life_rng.randf_range(LIFE_NEAR, LIFE_FAR)).normalized()
		var n := _life_rng.randi_range(2, 4) if k["herd"] else 1
		for i in n:
			var d := (at * pl.radius + t.rotated(u, i * 1.7) * i * 4.0).normalized()
			if pl.shape.sea > 0 and pl.shape.height(d) < 0.5:
				continue
			var c := CosmosCreature.new()
			c.cosmos = self
			c.setup(k, pl, _life_rng.randi())
			world.add_child(c)
			c.global_position = pl.global_position + d * (pl.radius + maxf(pl.shape.height(d), 0.0))
			creatures.append(c)
	# Pirate camps nearby: their props, and their guards turned out.
	for camp in camps_of(pl):
		var cp: Vector3 = camp[0]
		var dist := cp.distance_to(here)
		if dist < CAMP_NEAR * 3.0 and camp[1] == null:
			camp[1] = _build_camp(pl, cp)
		elif dist > CAMP_NEAR * 4.0 and camp[1] != null:
			(camp[1] as Node3D).queue_free()
			camp[1] = null
		if dist < CAMP_NEAR and int(camp[2]) < 3:
			# (its guards turn out one a tick - a model each: not all in one frame)
			for i in [int(camp[2])]:
				camp[2] = int(camp[2]) + 1
				var npc := CosmosNpc.new()
				npc.cosmos = self
				npc.setup(pl, cp, hash([cp, i]))
				world.add_child(npc)
				var u := cp.normalized()
				var off := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized().rotated(u, i * 2.1) * 6.0
				var d := (cp + off).normalized()
				npc.global_position = pl.global_position + d * (pl.radius + maxf(pl.shape.height(d), 0.0))
				npcs.append(npc)
		elif dist > CAMP_NEAR * 2.0 and int(camp[2]) > 0:
			camp[2] = 0   # (out of range: its guards stood down; they come out again)


## A pirate camp's props: a tent, crates, a mast with a red light, a glowing fire
## (no light of its own: a point light is another set of shaders for everything near it).
func _build_camp(pl: CosmosPlanet, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "PirateCamp"
	n.add_to_group("cam_solid")
	n.set_meta("cam_reach", 20.0)
	world.add_child(n)
	var u := at.normalized()
	var fwd := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized()
	n.global_transform = Transform3D(Basis.looking_at(fwd, u), pl.global_position + at)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)
	var cloth := CosmosStation._mat(Color(0.45, 0.12, 0.1), 0.0, 0.9)
	var metal := CosmosStation._mat(Color(0.3, 0.3, 0.32), 0.6, 0.5)
	var wood := CosmosStation._mat(Color(0.4, 0.3, 0.2), 0.0, 0.9)
	var tent := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.05
	tm.bottom_radius = 3.2
	tm.height = 3.2
	tm.radial_segments = 6
	tent.mesh = tm
	tent.material_override = cloth
	tent.position = Vector3(4, 1.5, 0)
	n.add_child(tent)
	for i in rng.randi_range(4, 8):
		var crate := MeshInstance3D.new()
		var s := rng.randf_range(0.7, 1.3)
		crate.mesh = CosmosStation._box(Vector3(s, s, s))
		crate.material_override = wood if i % 2 else metal
		crate.position = Vector3(rng.randf_range(-6, 0), s * 0.45, rng.randf_range(-5, 5))
		crate.rotation.y = rng.randf() * TAU
		n.add_child(crate)
	var mast := MeshInstance3D.new()
	mast.mesh = CosmosStation._cyl(0.12, 0.12, 8.0, 6)
	mast.material_override = metal
	mast.position = Vector3(-3, 4, -4)
	n.add_child(mast)
	var lamp := MeshInstance3D.new()
	lamp.mesh = CosmosStation._sphere(0.35)
	lamp.material_override = CosmosStation._mat(Color(1, 0.2, 0.1), 0.0, 0.5, Color(1.0, 0.15, 0.08) * 8.0)
	lamp.position = Vector3(-3, 8.2, -4)
	n.add_child(lamp)
	var fire := MeshInstance3D.new()
	fire.mesh = CosmosStation._sphere(0.6)
	fire.material_override = CosmosStation._mat(Color(1, 0.5, 0.1), 0.0, 0.5, Color(1.0, 0.45, 0.1) * 5.0)
	fire.position = Vector3(0, 0.2, 2)
	n.add_child(fire)
	return n


## The thing under the sights (on foot), the point aimed at, and how far.
func aim() -> Array:
	var o := cam.global_position
	var dir := -cam.global_basis.z
	var best: Node3D = null
	var bt := 400.0
	for list in [creatures, npcs]:
		for x in list:
			if not is_instance_valid(x) or x.get("dead"):
				continue
			var r: float = x.get("reach")
			var c: Vector3 = x.global_position + x.up() * maxf(r * 0.8, 0.9)
			var t := (c - o).dot(dir)
			if t > 0.0 and t < bt and (o + dir * t).distance_to(c) < r + 0.3:
				bt = t
				best = x
	if best == null and walker and walker.planet:
		var pl := walker.planet
		var t := 2.0
		while t < bt:
			var p := o + dir * t
			var local := p - pl.global_position
			if local.length() < pl.radius + pl.shape.surface(local.normalized()):
				bt = t
				break
			t += 2.0 + t * 0.03
	return [best, o + dir * bt, bt]


## The walker's rifle: a bolt from the muzzle at what the sights are on.
func walker_fire(w: CosmosWalker) -> void:
	var a := aim()
	var u := w.up()
	var muzzle := w.global_position + u * 1.35 + w.facing * 0.7 + w.facing.cross(u) * -0.25
	CosmosBolt.fire(self, muzzle, (a[1] as Vector3) - muzzle, "player", CosmosWalker.BOLT_DAMAGE)


func creature_died(c: CosmosCreature) -> void:
	kills += 1
	if hud:
		hud.flash("%s down" % c.kind["name"], 2.0)


func npc_died(_n: CosmosNpc) -> void:
	kills += 1
	if hud:
		hud.flash("Pirate down", 2.0)


## Downed on foot: the ship's drones bring you back to it, whole.
func walker_downed() -> void:
	if hud:
		hud.flash("Downed! Your ship's drones are bringing you back...", 3.0)
	get_tree().create_timer(2.5, false).timeout.connect(func():
		if walker == null or not is_instance_valid(walker):
			return
		var pl := walker.planet
		if pl == null:
			walker.revive(walker.global_position)
			return
		var at := ship.interior.to_global(ship.interior.ramp_foot() + Vector3(0, 0, 3.0))   # (by the foot of your ship's ramp)
		var local := at - pl.global_position
		walker.revive(pl.global_position + local.normalized() * (pl.radius + walker.floor_at(local) + 0.05))
		_shift_origin(true))


# --- Docking (stage 4) ------------------------------------------------------------

## The station near enough to dock at, or null.
func station_near() -> CosmosStation:
	for st: CosmosStation in stations:
		if st.global_position.distance_to(ship.global_position) - st.reach < DOCK_REACH:
			return st
	return null


## F: the station's traffic control takes the ship in - under the bay, up into it.
func request_dock() -> bool:
	var st := station_near()
	if st == null or ship.state != "fly" or docked:
		if hud:
			hud.flash("No station near enough to dock (within %s)" % CosmosHud._dist(DOCK_REACH))
		return false
	if ship.speed() > 250.0:
		hud.flash("Too fast to dock - slow under 250 m/s")
		return false
	var mouth := st.global_transform * st.bay
	var out := -st.global_basis.y
	var below := mouth + out * 180.0
	ship.state = "docking"
	ship.velocity = Vector3.ZERO
	ship.cruise = 0
	dock_station = st
	_dock = {"phase": 0, "t": 0.0, "from": ship.global_transform,
		"to": Transform3D(Basis.looking_at(-out, st.global_basis.z), below), "mouth": Transform3D(Basis.looking_at(-out, st.global_basis.z), mouth)}
	hud.flash("Docking at %s - traffic control has you" % label_of(st))
	return true


func _docking(delta: float) -> void:
	if _dock.is_empty():
		return
	_dock["t"] += delta
	var t: float = _dock["t"]
	match int(_dock["phase"]):
		0:   # (to below the bay, turning to face up into it)
			var k := smoothstep(0.0, 1.0, minf(t / 4.0, 1.0))
			ship.global_transform = (_dock["from"] as Transform3D).interpolate_with(_dock["to"], k)
			if t >= 4.0:
				_dock = {"phase": 1, "t": 0.0, "from": ship.global_transform, "to": _dock["mouth"]}
		1:   # (up into it, the screen going dark)
			var k := minf(t / 1.6, 1.0)
			ship.global_transform = (_dock["from"] as Transform3D).interpolate_with(_dock["to"], k * k)
			hud.fade = k
			if t >= 1.6:
				_enter_hangar(dock_station)
				_dock = {"phase": 2, "t": 0.0}
		2:   # (the hangar fading in)
			hud.fade = 1.0 - minf(t / 0.8, 1.0)
			if t >= 0.8:
				_dock = {}
		3:   # (undocking: dark, then out of the bay)
			hud.fade = minf(t / 0.6, 1.0)
			if t >= 0.6:
				_leave_hangar()
				_dock = {"phase": 4, "t": 0.0}
		4:
			hud.fade = 1.0 - minf(t / 0.8, 1.0)
			if t >= 0.8:
				_dock = {}


func _enter_hangar(st: CosmosStation) -> void:
	hangar = CosmosHangar.new()
	hangar.setup(st)
	world.add_child(hangar)
	# (a world of its own, far off the system's plane, out of sight of anything)
	hangar.global_transform = Transform3D(Basis.IDENTITY, st.global_position + Vector3(0, 90000.0, 0))
	var pad := hangar.to_global(CosmosHangar.PAD + Vector3(0, CosmosShip.GEAR, 0))
	ship.global_transform = Transform3D(Basis.looking_at(-hangar.global_basis.z, hangar.global_basis.y), pad)
	ship.state = "landed"
	ship.set_legs(true)
	ship.interior.ramp_end_y = -CosmosShip.GEAR
	ship.velocity = Vector3.ZERO
	ship.shield = ship.max_shield
	docked = true
	for x in npc_ships:
		x.queue_free()
	npc_ships.clear()
	_shift_origin(true)
	cam.follow(1.0)
	Galaxy.visit_station(str(st.record.get("id", "")))
	CosmosGame.missions.on_docked(str(st.record.get("name", "")))
	hud.flash("Docked at %s - E: get out, L / Space: undock" % label_of(st), 4.0)
	if not dry_run:
		CosmosGame.save(self)


## L / Space in the hangar: out of the bay into space.
func undock() -> void:
	if not docked or walker or not _dock.is_empty():
		return
	_dock = {"phase": 3, "t": 0.0}


func _leave_hangar() -> void:
	var st := dock_station
	if hangar:
		hangar.queue_free()
		hangar = null
	docked = false
	var mouth := st.global_transform * st.bay
	var out := -st.global_basis.y
	ship.global_transform = Transform3D(Basis.looking_at(out, st.global_basis.z), mouth + out * 60.0)
	ship.state = "fly"
	ship.velocity = out * 60.0
	ship.throttle = 0.3
	_shift_origin(true)
	cam.to_ship()
	cam.follow(1.0)
	hud.flash("Undocked from %s" % label_of(st))


## E in the hangar by a terminal: the station's service (Stage 5: the menus).
func terminal_here() -> Array:
	if walker == null:
		return []
	if walker.deck == ship.interior:
		var t := ship.interior.terminal_near(ship.interior.to_local(walker.global_position))
		return [t[0], "computer:%d" % int(t[1])] if not t.is_empty() else []
	if hangar == null:
		return []
	return hangar.terminal_near(hangar.to_local(walker.global_position))


func use_terminal(t: Array) -> void:
	var id := str(t[1])
	if id.begins_with("computer:"):
		open_computer(int(id.trim_prefix("computer:")))
	else:
		open_service(t[1])


## The ship's computer (the game's Ship Computer: inventory, repair bay,
## industry, tech, maps) at page `tab` - on your ship's terminals.
var _computer: Control
var _proxy: CosmosShipProxy


func open_computer(tab: int) -> void:
	if _computer == null:
		_computer = load("res://scenes/ship_menu.tscn").instantiate()
		_computer.data = CosmosGame.data
		_computer.ship = _proxy
		hud.get_parent().add_child(_computer)
		_computer.visibility_changed.connect(func():
			if not _computer.visible:
				if walker:
					walker.control = true
				if _may_capture():
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	if walker:
		walker.control = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_computer.open(tab)


## A station's service: the game's Station Menu (the same as the 2D game's -
## its look, its pages) on tab `tab`, for the station you're docked at.
var _station_menu: Control
var _station_proxy: CosmosStationProxy


func open_service(tab: Variant) -> void:
	if dock_station == null:
		return
	if _station_menu == null:
		_station_proxy = CosmosStationProxy.new()
		add_child(_station_proxy)
		_station_menu = load("res://scenes/station_menu.tscn").instantiate()
		_station_menu.data = CosmosGame.data
		_station_menu.ship = _proxy
		_station_menu.missions = CosmosGame.missions
		_station_menu.quest = CosmosGame.quest
		hud.get_parent().add_child(_station_menu)
		_station_menu.visibility_changed.connect(func():
			if not _station_menu.visible:
				if walker:
					walker.control = true
				ship.apply_upgrades()
				if _may_capture():
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	_station_proxy.setup(dock_station)
	if walker:
		walker.control = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_station_menu.open(_station_proxy)
	_station_menu.show_tab(int(tab) if tab is int else 1)


# --- Traffic and space combat (stage 4) ------------------------------------------

func _traffic() -> void:
	npc_ships = npc_ships.filter(func(x): return is_instance_valid(x) and not x.dead)
	var f := focus().global_position
	for x in npc_ships:
		if x.global_position.distance_to(f) > TRAFFIC_GONE and x != target:
			x.queue_free()
	if walker or ship.state != "fly" or docked:
		return
	var count := {"trader": 0, "patrol": 0, "pirate": 0}
	for x in npc_ships:
		count[x.kind] += 1
	var owner := Galaxy.owner_of(system_id)
	var rng := _life_rng
	# Traders passing by, between the system's stations and planets.
	var stops: Array = stations + planets.filter(func(p): return p.shape.kind != "gas")
	if count["trader"] < 3 and stops.size() >= 2:
		var t := CosmosNpcShip.new()
		t.setup("trader", self, rng.randi(), str(stops[0].record.get("empire", owner)) if stops[0] is CosmosStation else owner)
		world.add_child(t)
		var dir := Vector3(rng.randfn(), rng.randfn() * 0.3, rng.randfn()).normalized()
		t.global_position = f + dir * rng.randf_range(TRAFFIC_NEAR, TRAFFIC_FAR)
		t.dest = stops[rng.randi() % stops.size()]
		t.look_at(t.dest.global_position, Vector3.UP)
		npc_ships.append(t)
	# Patrols round the nearest station.
	var near_st: CosmosStation = null
	for st: CosmosStation in stations:
		if st.global_position.distance_to(f) < 25000.0:
			near_st = st
	if near_st and count["patrol"] < 2 and owner != "pirates":
		var p := CosmosNpcShip.new()
		p.setup("patrol", self, rng.randi(), owner)
		world.add_child(p)
		p.global_position = near_st.global_position + Vector3(rng.randfn(), rng.randfn() * 0.2, rng.randfn()).normalized() * (near_st.reach + 1500.0)
		p.home = near_st
		npc_ships.append(p)
	# Pirates: now and then, more in lawless systems.
	if count["pirate"] == 0 and _pirate_cd <= 0.0:
		_pirate_cd = rng.randf_range(60.0, 140.0) / maxf(Galaxy.pirate_level(system_id), 0.2)
		var n := rng.randi_range(1, 3)
		var dir := Vector3(rng.randfn(), rng.randfn() * 0.3, rng.randfn()).normalized()
		for i in n:
			var pz := CosmosNpcShip.new()
			pz.setup("pirate", self, rng.randi(), "pirates")
			world.add_child(pz)
			pz.global_position = ship.global_position + dir * 7000.0 + Vector3(rng.randfn(), rng.randfn(), rng.randfn()) * 300.0
			pz.look_at(ship.global_position, Vector3.UP)
			npc_ships.append(pz)
		hud.flash("Pirates! %d raider%s closing in" % [n, "s" if n > 1 else ""], 4.0)


## Where the ship's lasers aim: a targeted ship ahead (led), else the sights' line.
func ship_aim() -> Vector3:
	var fwd := -cam.global_basis.z
	if target is CosmosNpcShip and is_instance_valid(target):
		var t: CosmosNpcShip = target
		var to := t.global_position - ship.global_position
		if to.normalized().dot(fwd) > 0.93 and to.length() < 3000.0:
			return t.global_position + (t.velocity - ship.velocity) * (to.length() / CosmosBolt.SPACE_SPEED)
	return cam.global_position + fwd * 2500.0


func ship_destroyed(s: CosmosNpcShip) -> void:
	npc_ships.erase(s)
	if target == s:
		target = null
	if s.kind == "pirate":
		var b := 400 + _life_rng.randi_range(0, 400)
		bounty += b
		CosmosGame.data.add_credits(b)
		var msg := "Raider destroyed - bounty %d dr" % b
		var ct: Dictionary = CosmosGame.extra.get("contract", {})
		if not ct.is_empty() and ct.get("system", "") == system_id:
			ct["done"] = int(ct.get("done", 0)) + 1
			if ct["done"] >= int(ct["need"]):
				CosmosGame.data.add_credits(int(ct["reward"]))
				msg = "Contract fulfilled! %d dr paid" % int(ct["reward"])
				CosmosGame.extra.erase("contract")
		hud.flash(msg, 3.0)
	else:
		hud.flash("%s destroyed" % s.label, 3.0)


func trader_arrived(s: CosmosNpcShip) -> void:
	npc_ships.erase(s)
	s.queue_free()


## The ship lost: an explosion, and you back by the first station, repaired.
func ship_lost() -> void:
	CosmosBoom.at(self, ship.global_position, 14.0)
	hud.flash("Your ship was destroyed - recovered at %s" % (label_of(stations[0]) if not stations.is_empty() else "the star"), 4.0)
	ship.hull = ship.max_hull
	ship.shield = ship.max_shield
	ship.velocity = Vector3.ZERO
	ship.cruise = 0
	for x in npc_ships:
		if x.kind == "pirate":
			x.queue_free()
	npc_ships = npc_ships.filter(func(x): return x.kind != "pirate")
	_place_ship()


## Keeps the other ships out of planets and stations.
func bump_npc(s: Node3D) -> void:
	for pl: CosmosPlanet in planets:
		var d := s.global_position - pl.global_position
		var r := pl.radius + pl.shape.top() + 300.0
		if d.length() < r:
			s.global_position = pl.global_position + d.normalized() * r
	for st: CosmosStation in stations:
		var d := s.global_position - st.global_position
		if d.length() < st.reach * 0.7:
			s.global_position = st.global_position + d.normalized() * st.reach * 0.7


# --- Input, the menu ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not built:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				_toggle_menu()
			KEY_T:
				pick_target()
			KEY_TAB, KEY_I:
				if _computer and _computer.visible:
					_computer.close()
				else:
					open_computer(0)
			KEY_H:
				hud.show_help = not hud.show_help
			KEY_L:
				if walker == null:
					if ship.state == "fly":
						land()
					elif ship.state == "landed":
						undock() if docked else ship.take_off()
			KEY_E:
				if walker:
					var term := terminal_here()
					if not term.is_empty():
						use_terminal(term)
					else:
						board()
				elif ship.state == "landed":
					get_out()
			KEY_G:
				if walker == null and ship.state == "fly":
					get_out()   # (up from the seat in flight - the ship flies on)
			KEY_SPACE:
				if walker == null and ship.state == "landed":
					undock() if docked else ship.take_off()
			KEY_F:
				if walker == null and ship.state == "fly":
					request_dock()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _menu and not _menu.visible:
		if event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _may_capture():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif walker:
			walker.trigger = event.pressed
		else:
			ship.trigger = event.pressed


## The 2D game's HUD over the 3D view (the same look): the health gauge
## (hull, shields, fuel - on foot the automaton's health), the radar (fed by
## CosmosMapMirror), the toolbar, the event console, messages; Tab opens the
## Ship Computer; the tutorial's icon opens its book there.
var hud2d: CanvasLayer
var _mirror: CosmosMapMirror


func _build_game_hud() -> void:
	_proxy = CosmosShipProxy.new()
	_proxy.cosmos = self
	add_child(_proxy)
	_mirror = CosmosMapMirror.new()
	_mirror.cosmos = self
	add_child(_mirror)
	hud2d = load("res://scenes/hud.tscn").instantiate()
	hud2d.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(hud2d)
	hud2d.bind(_proxy, CosmosGame.data)
	hud2d.toolbar.slot_pressed.connect(_use_slot)
	hud2d.hint.visible = false   # (the 2D game's click-to-fly hints: not here - the tutorial's icon instead)
	hud2d.gauge.shape_source = func(): return ProcArt.get_tex("ship_player")
	if hud2d.mining_panel:
		hud2d.mining_panel.process_mode = Node.PROCESS_MODE_DISABLED   # (no mining in the 3D game yet)
		hud2d.mining_panel.visible = false
	# The tutorial: an icon (top right, under the radar) - its book in the Ship Computer's Archive.
	var tut := Button.new()
	tut.name = "TutorialButton"
	EditorIcons.dress(tut, "help", EditorIcons.tip("Tutorial", "Tab", "The tutorial: how to play - in the Ship Computer's Archive."))
	tut.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tut.offset_left = -64
	tut.offset_top = 300
	tut.offset_right = -16
	tut.offset_bottom = 348
	tut.pressed.connect(open_tutorial)
	tut.text = ""
	tut.expand_icon = true
	hud2d.add_child(tut)


func open_tutorial() -> void:
	open_computer(6)   # (ShipMenu.ARCHIVE_TAB)
	var arch: Node = _computer.page(6)
	if arch and arch.has_method("open_book"):
		arch.open_book("tutorial")


## A toolbar slot: what's on it used (a repair kit, an energy drink...).
func _use_slot(i: int) -> void:
	var slot: Dictionary = hud2d.toolbar.slot_at(i)
	var id := str(slot.get("id", ""))
	if id == "repair_kit":
		_proxy.use_system(id)
		hud.flash("Repair kit used")
	elif id != "":
		hud.flash(Items.display_name(id))


## The 2D HUD's gauge on what you are: the ship, or you on foot.
func _gauge_on_walker(on: bool) -> void:
	if hud2d == null or hud2d.gauge == null:
		return
	var g: HealthGauge = hud2d.gauge
	if on:
		g.which = "automaton"
		g.shape_source = func(): return null
		g.read = func(): return [walker.hp if walker else 100.0, CosmosWalker.MAX_HP, 0.0, 0.0] if is_instance_valid(walker) else [100.0, 100.0, 0.0, 0.0]
		g.fuel = func(): return [CosmosGame.data.stamina, Stamina.MAX, 0.0]
		g.fuel_name = "Stamina"
	else:
		g.which = "ship"
		g.shape_source = func(): return ProcArt.get_tex("ship_player")
		g.read = func(): return [ship.hull, ship.max_hull, ship.shield, ship.max_shield]
		g.fuel = func(): return [CosmosGame.data.fuel_level(), CosmosGame.data.fuel_max(), Shipyard.FUEL_JUMP]
		g.fuel_name = "Fuel"


## The mouse is captured for steering - not in a test, a tour or a bot's window.
func _may_capture() -> bool:
	return DisplayServer.get_name() != "headless" and not Settings.bot_arg()


func _build_menu(layer: CanvasLayer) -> void:
	_menu = PanelContainer.new()
	_menu.visible = false
	_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_menu.add_child(box)
	var title := Label.new()
	title.text = "SPACE ATRAPOS 3D"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for b in [["Resume", _toggle_menu], ["Save game", func():
				hud.flash("Game saved" if CosmosGame.save(self) else "Couldn't save"); _toggle_menu()], ["Back to the title screen", _quit], ["Exit to desktop", _exit_desktop]]:
		if b[0] == "Exit to desktop" and Settings.on_web():
			continue   # (a browser tab: closed by the browser)
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(360, 52)
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(b[1])
		box.add_child(btn)
	layer.add_child(_menu)
	_menu.reset_size()
	_menu.position = (Vector2(get_viewport().get_visible_rect().size) - _menu.size) * 0.5


func _toggle_menu() -> void:
	_menu.visible = not _menu.visible
	get_tree().paused = _menu.visible
	ship.control = not _menu.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _menu.visible or not _may_capture() else Input.MOUSE_MODE_CAPTURED
	if _menu.visible:
		(_menu.get_child(0).get_child(1) as Button).grab_focus()


## Exit to desktop (the Esc menu): the game saved first, then the window closed.
func _exit_desktop() -> void:
	if not dry_run:
		CosmosGame.save(self)
	get_tree().quit()


func _quit() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	arrive_from = ""
	UI.switch_scene("res://main_menu.tscn")


func _exit_tree() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
