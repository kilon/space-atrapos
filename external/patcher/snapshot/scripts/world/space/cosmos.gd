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

const SCENE := "res://scenes/world/cosmos.tscn"
const SHIFT_AT := 2500.0
const LOD_HZ := 30.0
const LOD_SLOW_HZ := 8.0
const NOISE_SIZE := 64
const ORBIT_SLOWDOWN := 4.0   # (the galaxy map's orbits: periods as the old game had them)
const SKY := preload("res://shaders/world/sky.gdshader")

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
var mining: CosmosMining        # the mining beam and its rock
var deposits: CosmosDeposits    # the minerals on the ground round you, on foot (and your mining beam)
var target: Node3D = null
var target_view: CosmosTargetView   # (the target's window, top left)
var noise: Texture3D
var built := false
var origin := Vector3.ZERO      # (how far the world has been moved back: system frame = world + origin)
var _lod_t := 0.0
var _gate_side := {}
var _terminal: Control
var _env: Environment
var _shells_on := true
const AMBIENT_OUT := Color(0.11, 0.12, 0.15)
const AMBIENT_SKY := Color(0.4, 0.42, 0.46)   # (on a world with air, by day: the sky's light in the shade)
const AMBIENT_DUSK := Color(0.46, 0.33, 0.34)  # (by the dawn and the dusk: the sky's light warm and rosy)
const AMBIENT_NIGHT := Color(0.2, 0.22, 0.3)  # (by night near the ground: the stars', the moons' - cool, dim; less where there's no air)
const AMBIENT_UNDER := Color(0.4, 0.37, 0.34)  # (under the ground - a cave, a tunnel, a dungeon: never pitch black)
const AMBIENT_IN := Color(0.42, 0.43, 0.46)    # (inside the ship: its lights all round)
const AMBIENT_HALL := Color(0.46, 0.44, 0.42)  # (in a station's hangar: its light panels and lamps all round - its crew seen, not silhouettes)
var _jumping := false
var docked := false              # (stage 4: in a station's hangar)
var hangar: CosmosHangar = null
var law: CosmosLaw = null        # (the stations' law, their guns, sieges: CosmosLaw)
var dock_station: CosmosStation = null
var _dock := {}                  # the docking or undocking under way: {phase, t, from, to}
const DOCK_REACH := 2500.0       # F works this close to a station's ring
const PAD_SPEED := 12.0          # m/s: set down on a pad slower than this
const PAD_ALIGN := 12.0          # degrees: set down on a pad with the nose this near its axis (toward the station - the pad's top)


## The way a ship on pad `xf` faces: its nose to the pad's top edge (toward
## the station), its engines to the bottom - square on it, every ship.
static func pad_nose(xf: Transform3D) -> Vector3:
	return -xf.basis.x.normalized()


## How far (degrees) the ship's heading is off the pad's axis, flat on the pad.
static func pad_heading_off(xf: Transform3D, fwd: Vector3) -> float:
	var u := xf.basis.y.normalized()
	var f := (fwd - u * fwd.dot(u))
	if f.length() < 0.01:
		return 180.0
	return rad_to_deg(f.normalized().angle_to(pad_nose(xf)))
const LIFT_DEPTH := 60.0         # m: a pad's lift, down into the station
const LIFT_TIME := 9.0           # s: down the shaft into the port's hall (or up)
const HATCH_TIME := 1.8          # s: a pad's shutters sliding shut over its shaft, or open
var dock_pad := {}               # the pad the station gave you (CosmosStation.pads)
var jumped_to := ""
## Life on the planet you're on (stage 3): its animals and its pirates round you.
var creatures: Array = []       # CosmosCreature
var npcs: Array = []            # CosmosNpc
var kills := 0
var _life_t := 0.0
var _towns := {}                # CosmosPlanet -> [CosmosTown or null] (its sites' order)
var monsters: Array = []         # the space monsters out (CosmosMonster)
var lairs: Array = []            # the system's monster signals (CosmosLair)
const LAIR_NEAR := 9000.0        # a lair's creature comes out within this
var citizens: Array = []         # the towns' people (CosmosNpc, role "citizen")
const TOWN_NEAR := 4500.0        # a town is built within this (m), freed past 1.4 x
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
var sandbox: CosmosSandbox       # the towns' ore buyers, couriers and pilots; the scanner; bounty vouchers
var tutor: Node                  # the interactive tutorial (CosmosTutor)
var veins: CosmosVeins           # ore veins in the ground round you
var builds: CosmosBuilds         # your buildings on the world you're on, and the builder (BuildKit's pieces)
var underwater: CosmosUnderwater # the look under the sea and its life (kelp, corals, fish...)
var _rays: CosmosGodRays          # (the sun's rays: _god_rays)
var weather_fx: CosmosWeatherFx  # the weather (PlanetWeather): rain, snow, ash round you, storms - `now` where you are
var _traffic_t := 0.0
var _pirate_cd := 120.0
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
	LiveEdits.hook(get_tree())   # (the Live Editor's kept edits put back on what's made from now on)
	add_child(world)
	law = CosmosLaw.new()
	law.name = "Law"
	law.cosmos = self
	law.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(law)
	_build()


## The game as a save (SaveGame's quicksave, autosave, the Esc menu's slots).
func get_save_data() -> Dictionary:
	return CosmosGame.snapshot(self)


## Built and every planet's first patches in (the loading veil waits for it).
func build_settled() -> bool:
	if not built or _resuming:
		return false
	if OS.has_feature("web") and not CosmosWarm.drawn:
		return false   # (a browser: what's seen first not drawn once yet - its shaders compiled under the loading screen, not in play)
	for p: CosmosPlanet in planets:
		if not p.settled():
			return false
	return true


func _stage() -> void:
	await get_tree().process_frame


func _build() -> void:
	while not CosmosWarm.loads_done():
		await _stage()   # (the title's background loads - the HUD, you, the start city's people: in, not load()ed in a frame; nothing else on the threads meanwhile)
	if OS.has_feature("web"):
		while CosmosWarm.load_direct():
			await _stage()   # (a browser: the scripts and the HUD loaded here, a thing a frame)
		CosmosWarm.draw_in(self, ["_walker", "_citizen", "_town", "_flora", "_creature", "_deposit", "_fx", "_fx_smoke", "_fx_debris", "_roads", "_loot"])   # (and what's seen first drawn once, a thing a frame, while this builds)
	var have_ship := not bool(CosmosGame.extra.get("no_ship", false))
	if have_ship or not OS.has_feature("web"):
		CosmosShip.start_hull(have_ship)        # (your ship's hull and rooms: on workers meanwhile - soon if you have one; in a browser, none yet - not till you've one)
	var flying := [str(Galaxy.system(system_id).get("owner", "")), "pirates"]   # (whose ships fly here: the system's, its stations', the raiders')
	for sid0 in Galaxy.system(system_id).get("stations", []):
		var e0 := str(Galaxy.stations.get(sid0, {}).get("empire", ""))
		if not flying.has(e0):
			flying.append(e0)
	EmpireHulls.warm(flying)
	if have_ship or not OS.has_feature("web"):
		CosmosShipInterior.start_dress(have_ship)
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
		var at := _orbit_pos(r, where)
		p.sun_hint = (star.global_position - at).normalized()   # (its towns on its day side)
		p.setup(r, noise)
		where[r["id"]] = at
		p.position = at - origin
		world.add_child(p)
		_orbit_body(p, "planet:" + str(r["id"]), Vector3.ZERO, 0.0, clampf(p.radius * 5.0, 6000.0, 20000.0))
		p.set_sun((star.global_position - p.global_position).normalized())
		planets.append(p)
		await _stage()
	var sys: Dictionary = Galaxy.system(system_id)
	for sid in sys.get("stations", []):
		var st: Dictionary = Galaxy.stations.get(sid, {})
		if st.is_empty():
			continue
		var s := CosmosStation.new()
		s.setup(st, true)   # (its parts laid out: a loading step; its solids and the bake's start: the next)
		world.add_child(s)
		s.position = co_orbit(system_id, "station:" + str(sid), _map3(st["pos"], hash(sid)), STATION_CLEAR, Galaxy.time, planet_places(system_id, Galaxy.time)) - origin
		_orbit_body(s, "station:" + str(sid), _map3(st["pos"], hash(sid)), STATION_CLEAR, s.reach + 2500.0)
		stations.append(s)
		await _stage()
		s.finish()
		await _stage()
	for sg in Galaxy.signals_in(system_id):
		if str(sg.get("kind", "")) == "monster" and not bool(sg.get("done", false)):
			var lr := CosmosLair.new()
			lr.sig = sg
			lr.name = "Lair"
			world.add_child(lr)
			var pos: Array = sg["pos"]
			var lp0 := _map3(Vector2(float(pos[0]), float(pos[1])), hash(str(sg["id"])))
			lr.position = co_orbit(system_id, "lair:" + str(sg["id"]), lp0, LAIR_CLEAR, Galaxy.time, planet_places(system_id, Galaxy.time)) - origin
			_orbit_body(lr, "lair:" + str(sg["id"]), lp0, LAIR_CLEAR, 6000.0)
			lairs.append(lr)
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
		rocks.setup(hash(system_id) + i, noise, "%s:%d" % [system_id, i])
		world.add_child(rocks)
		rocks.position = co_orbit(system_id, "field:%d" % i, _map3(f, i * 31), CosmosRocks.SPREAD * 1.5, Galaxy.time, planet_places(system_id, Galaxy.time)) - origin
		_orbit_body(rocks, "field:%d" % i, _map3(f, i * 31), CosmosRocks.SPREAD * 1.5, CosmosRocks.SPREAD * 1.6)
		fields.append(rocks)
		i += 1
	mining = CosmosMining.new()
	mining.cosmos = self
	world.add_child(mining)
	await _stage()
	if not OS.has_feature("web"):
		while not (CosmosShip.hull_ready() and CosmosShipInterior.dress_ready()):
			await _stage()   # (the desktop: a moment - its hull and rooms in before it's shown, no mesh swapped in during play)
	ship = CosmosShip.new()   # (a browser: not waited for - its hull a stand-in, its rooms empty, till their workers are done: parts_in)
	ship.cosmos = self
	world.add_child(ship)
	ship.apply_upgrades()
	ship.hull = float(CosmosGame.extra.get("hull", ship.max_hull))
	ship.shield = float(CosmosGame.extra.get("shield", ship.max_shield))
	ship.apply_upgrades()
	_place_ship()
	ship.set_process(false)   # (it flies once everything's built: the last pieces come a frame each)
	await _stage()
	cam = CosmosCam.new()
	if not CosmosPlanet.COMPAT:   # (the sun's rays through the clouds and the trees: a compute pass after the transparent things - not in the browser's renderer)
		_rays = CosmosGodRays.new()
		var comp := Compositor.new()
		comp.compositor_effects = [_rays]
		cam.compositor = comp
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
	hud.visible = false
	layer.add_child(hud)
	sandbox = CosmosSandbox.new()
	sandbox.set("cosmos", self)   # (set, not typed-assigned: the script reloads live - its own type is a new one then)
	add_child(sandbox)
	CosmosCaravans.attach(self)   # (the roads between the towns, their travellers, the loot of the dead: CosmosRoads, CosmosLoot)
	builds = CosmosBuilds.new()   # (your buildings: raised on their world as you come to it)
	builds.cosmos = self
	add_child(builds)
	veins = CosmosVeins.new()   # (ore veins in the ground: dug with the terrain digger, shown by the scanner)
	veins.cosmos = self
	world.add_child(veins)
	weather_fx = CosmosWeatherFx.new()   # (the weather: the worlds' clouds and ground, what falls round you, storms)
	weather_fx.cosmos = self
	add_child(weather_fx)
	underwater = CosmosUnderwater.new()   # (under a sea: the water's look, its plants, rocks and animals)
	underwater.cosmos = self
	add_child(underwater)
	tutor = CosmosTutor.new()   # (the interactive tutorial: a new game's; hidden when there's none)
	tutor.set("cosmos", self)
	add_child(tutor)
	target_view = CosmosTargetView.new()
	target_view.cosmos = self
	target_view.process_priority = 20   # (after the camera's moved)
	layer.add_child(target_view)
	await _stage()
	_build_pause_menu()
	await _stage()
	_build_game_hud()
	if OS.has_feature("web"):
		await _stage()
		_make_computer()   # (a browser: the Automaton's screen made now - and its inventory page shown once, under the loading screen: its first opening in play was a long frame)
		_computer.open(0)
		await _stage()
		await _stage()
		_computer.visible = false
	# (the game HUD's pieces shown one a frame: each one's first draw - its glyphs, its icons - a frame of its own)
	var pieces: Array = []
	for ch in hud2d.get_children():
		if ch is CanvasItem and (ch as CanvasItem).visible:
			(ch as CanvasItem).visible = false
			pieces.append(ch)
	for ch in pieces:
		await _stage()
		if is_instance_valid(ch):
			(ch as CanvasItem).visible = true
	await _stage()
	hud.visible = true
	ship.set_process(not ship_elsewhere)
	_orbit_watch()   # (the worlds in motion: what's near each carried with it)
	built = true
	_resume_on_foot()
	_update_lod(true)
	if _may_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.flash("%s - %s" % [system_title(), "arrived through the gate" if arrive_from != "" else ("your game, continued" if CosmosGame.from_save else "a new game")])
	if arrive_from != "" and not dry_run and DisplayServer.get_name() != "headless":
		# (the arrival's autosave: a moment on - not in the frame the game's HUD is made)
		get_tree().create_timer(0.4).timeout.connect(func():
			if is_inside_tree() and built:
				CosmosGame.save(self))


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


## Its build collected if it was started (leaving the game: no task left in the pool).
static func finish_tasks() -> void:
	if _noise_task != -1:
		WorkerThreadPool.wait_for_task_completion(_noise_task)
		_noise_task = -1


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
	RenderingServer.environment_glow_set_use_bicubic_upscale(false)   # (linear: ~0.05 ms less a frame, the bloom as soft)
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
		for o in Galaxy.HOME_ORBITS:
			var pd: Dictionary = Planets.PLANETS.get(o[0], {})
			var tpl := str(pd.get("template", "barren"))
			out.append({"id": o[0], "name": pd.get("name", o[0]), "type": types.get(tpl, "moon"), "template": tpl,
				"variant": int(pd.get("variant", 0)), "size": o[3], "orbit": o[1], "phase": o[2],
				"seed": int(pd.get("seed", hash(o[0]) % 100000)), "moon_of": o[4]})
	return out


func _orbit_pos(r: Dictionary, where: Dictionary) -> Vector3:
	return orbit_pos_at(r, where, Galaxy.time)


# --- The worlds in motion: orbits ----------------------------------------------------
## Every world goes round its star (a moon round its world) on the galaxy's clock
## (Galaxy.time) - in the game as on the maps, from these same functions. What
## lies in a world's orbit band - stations, asteroid fields, lairs - co-orbits
## that world, keeping its place from it (so a world never sweeps through one);
## what's further out stays put. In the game (_orbit_tick) whatever is near a
## moving body - you, your ship, the camera, ships, creatures - is carried along
## with it: by the body whose reach holds it (the smallest).

const ANCHOR_BAND := 15000.0     # m from a world's orbit: within it a thing co-orbits that world
static var _orbit_cache := {}    # system id -> {recs, by_id, anchors}

## The orbit's period (s).
static func orbit_period(r: Dictionary) -> float:
	var moon := str(r.get("moon_of", "")) != ""
	return (240.0 if moon else 900.0 * pow(float(r["orbit"]) / 3000.0, 1.5)) * ORBIT_SLOWDOWN


## The orbit's angle at galaxy time `t`.
static func orbit_angle(r: Dictionary, t: float) -> float:
	return float(r["phase"]) + t * TAU / orbit_period(r)


## A point of a world's orbit (m, round what it circles) at angle `a` - its tilt the record's own.
static func orbit_point(r: Dictionary, a: float) -> Vector3:
	var tl: Vector2 = _tilts.get(r["id"], Vector2.INF)
	if tl == Vector2.INF:   # (its tilt and the tilt's turn: drawn once from its id)
		var moon := str(r.get("moon_of", "")) != ""
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(r["id"]) + ":incline")
		var tilt := rng.randf_range(-0.06, 0.06) if not moon else rng.randf_range(-0.3, 0.3)
		tl = Vector2(sin(tilt), rng.randf() * TAU)
		_tilts[r["id"]] = tl
	var flat := Vector2.from_angle(a) * float(r["orbit"]) * PlanetShape.PX_TO_M
	return Vector3(flat.x, flat.length() * tl.x * sin(a + tl.y), flat.y)

static var _tilts := {}


## A world's place at galaxy time `t` (m, round the star); `where` has its world's when it's a moon.
static func orbit_pos_at(r: Dictionary, where: Dictionary, t: float) -> Vector3:
	var p := orbit_point(r, orbit_angle(r, t))
	var parent := str(r.get("moon_of", ""))
	if parent != "":
		p += where.get(parent, Vector3.ZERO)
	return p


static func _orbits_of(sid: String) -> Dictionary:
	var sys: Dictionary = Galaxy.system(sid)
	if not _orbit_cache.has(sid) or not is_same(_orbit_cache[sid]["sys"], sys):   # (a new game's galaxy: worked out again)
		var recs := planet_records(sid)
		var by_id := {}
		for r in recs:
			by_id[str(r["id"])] = r
		_orbit_cache[sid] = {"recs": recs, "by_id": by_id, "anchors": {}, "sys": sys}
	return _orbit_cache[sid]


## Every world's place at galaxy time `t`: id -> m round the star.
static func planet_places(sid: String, t: float) -> Dictionary:
	var where := {}
	for r in _orbits_of(sid)["recs"]:
		where[str(r["id"])] = orbit_pos_at(r, where, t)
	return where


## Where a thing laid out at `p0` (m, round the star: the map's place) is at
## galaxy time `t` - co-orbiting the world whose orbit band it's in (kept `clear`
## m off that world's air and its moons' orbits), else where it was laid out.
## `where`: planet_places(sid, t).
static func co_orbit(sid: String, key: String, p0: Vector3, clear: float, t: float, where: Dictionary) -> Vector3:
	var O := _orbits_of(sid)
	var an: Dictionary = O["anchors"]
	if not an.has(key):
		an[key] = _anchor(O, p0, clear)
	var a: Array = an[key]
	if str(a[0]) == "":
		return p0
	var r: Dictionary = O["by_id"][a[0]]
	var da := orbit_angle(r, t) - orbit_angle(r, 0.0)
	return where.get(str(a[0]), Vector3.ZERO) + (a[1] as Vector3).rotated(Vector3.UP, -da)


## Which world a thing at `p0` rides with, and its place from that world then (at time 0): [id, offset] or ["", p0].
static func _anchor(O: Dictionary, p0: Vector3, clear: float) -> Array:
	var best := ""
	var best_d := INF
	var flat0 := Vector2(p0.x, p0.z).length()
	for r in O["recs"]:
		if str(r.get("moon_of", "")) != "":
			continue
		var pr := float(r.get("size", 500.0)) * PlanetShape.SIZE_TO_R
		var band := maxf(ANCHOR_BAND, pr * 1.2 + clear)
		for m in O["recs"]:
			if str(m.get("moon_of", "")) == str(r["id"]):
				band = maxf(band, float(m["orbit"]) * PlanetShape.PX_TO_M * 1.05 + float(m.get("size", 200.0)) * PlanetShape.SIZE_TO_R + clear)
		var d := absf(flat0 - float(r["orbit"]) * PlanetShape.PX_TO_M)
		if d < band and d < best_d:
			best_d = d
			best = str(r["id"])
	if best == "":
		return ["", p0]
	var where0 := planet_places_from(O, 0.0)
	var off: Vector3 = p0 - (where0[best] as Vector3)
	var pr0 := float(O["by_id"][best].get("size", 500.0)) * PlanetShape.SIZE_TO_R
	var dirv := off.normalized() if off.length() > 1.0 else Vector3.RIGHT
	var dist := maxf(off.length(), pr0 * 1.2 + clear)   # (clear of its air)
	for m in O["recs"]:   # (and of its moons' orbits: past the shell they run on)
		if str(m.get("moon_of", "")) != best:
			continue
		var mo := float(m["orbit"]) * PlanetShape.PX_TO_M
		var mr := float(m.get("size", 200.0)) * PlanetShape.SIZE_TO_R + clear
		if dist > mo - mr and dist < mo * 1.05 + mr:
			dist = mo * 1.05 + mr
	return [best, dirv * dist]


static func planet_places_from(O: Dictionary, t: float) -> Dictionary:
	var where := {}
	for r in O["recs"]:
		where[str(r["id"])] = orbit_pos_at(r, where, t)
	return where


## Where everything that moves in system `sid` is at galaxy time `t` (m, round
## the star): "planet:<id>", "station:<id>", "field:<i>" (its laid-out places as
## the game makes them) - for the maps away from the game (the game's own nodes
## are moved by _orbit_tick).
static func system_places(sid: String, t: float) -> Dictionary:
	var where := planet_places(sid, t)
	var out := {}
	for id in where:
		out["planet:" + str(id)] = where[id]
	var sys: Dictionary = Galaxy.system(sid)
	for stid in sys.get("stations", []):
		var st: Dictionary = Galaxy.stations.get(stid, {})
		if not st.is_empty():
			out["station:" + str(stid)] = co_orbit(sid, "station:" + str(stid), _map3(st["pos"], hash(stid)), STATION_CLEAR, t, where)
	var i := 0
	for f in sys.get("fields", []):
		out["field:%d" % i] = co_orbit(sid, "field:%d" % i, _map3(f, i * 31), CosmosRocks.SPREAD * 1.5, t, where)
		i += 1
	return out


const STATION_CLEAR := 4500.0    # m: a station kept this far off a world's air (its reach and more)
const LAIR_CLEAR := 3000.0


# (in the game: the bodies moved each frame, what's near them carried along)
var _bodies: Array = []          # [node, key, laid-out place, clearance, reach, radius] - the planets first
var _movers: Array = []          # the world's other nodes
var _rides := {}                 # node -> its body's index (-1: none) - looked at again a few a frame
var _ride_new: Array = []        # (nodes just added: given their body next frame, once placed)
var _ride_i := 0
var _orbit_t := -1.0
var _sun_t := 0.0
const RIDE_LOOKS := 24           # movers looked at again a step
const ORBIT_HZ := 30.0           # (steps a second: everything near a body moves with it in the same step - a world's 1.5 m a step unseen)

func _orbit_body(n: Node3D, key: String, p0: Vector3, clear: float, reach: float) -> void:
	_bodies.append([n, key, p0, clear, reach, float(n.radius) if n is CosmosPlanet else 0.0])


## The world's nodes followed as they come and go (the bodies' riders).
func _orbit_watch() -> void:
	var is_body := {}
	for b in _bodies:
		is_body[b[0]] = true
	for c in world.get_children():
		if not is_body.has(c) and c is Node3D:
			_movers.append(c)
			_ride_new.append(c)
	world.child_entered_tree.connect(func(n: Node):
		if n.get_parent() == world and n is Node3D and not is_body.has(n):
			_movers.append(n)
			_ride_new.append(n))
	world.child_exiting_tree.connect(func(n: Node):
		if _rides.has(n):
			_rides.erase(n)
		_movers.erase(n)
		_ride_new.erase(n))


## The body a node rides with, or -1: of those whose reach holds it, the one
## whose surface is nearest (on a world's ground: that world - not a moon overhead
## whose reach happens to cover it; a ship docked at a station: the station).
func _ride_of(n: Node3D) -> int:
	var p := n.position
	var best := -1
	var best_d := INF
	for i in _bodies.size():
		var b: Array = _bodies[i]
		var r: float = b[4]
		var d2 := p.distance_squared_to((b[0] as Node3D).position)
		if d2 < r * r:
			var d := sqrt(d2) - float(b[5])   # (how far from its surface)
			if d < best_d:
				best = i
				best_d = d
	return best


## The worlds on along their orbits (and what rides with them), to Galaxy.time;
## each node near one carried by as much as its body moved.
func _orbit_tick(_delta: float) -> void:
	var t: float = Galaxy.time
	if _bodies.is_empty() or absf(t - _orbit_t) < 1.0 / ORBIT_HZ:
		return
	var step := clampf(t - _orbit_t, 0.0, 1.0) if _orbit_t >= 0.0 else 0.0
	_orbit_t = t
	var where := planet_places(system_id, t)
	var moved: Array = []
	moved.resize(_bodies.size())
	for i in _bodies.size():
		var b: Array = _bodies[i]
		var n: Node3D = b[0]
		var key: String = b[1]
		var at: Vector3
		if key.begins_with("planet:"):
			at = where.get(key.substr(7), n.position + origin)
		else:
			at = co_orbit(system_id, key, b[2], b[3], t, where)
		var d: Vector3 = at - origin - n.position
		n.position += d
		moved[i] = d
		if n is CosmosLair and is_instance_valid(n.monster):
			n.monster.lair += d   # (its monster's home ground goes with it)
	for n in _ride_new:   # (newly added: their body)
		if is_instance_valid(n):
			_rides[n] = _ride_of(n)
	_ride_new.clear()
	var m := _movers.size()
	for k in mini(RIDE_LOOKS, m):   # (a few a frame looked at again: who's come into or left a body's reach)
		_ride_i = (_ride_i + 1) % m
		var n: Node3D = _movers[_ride_i]
		if is_instance_valid(n):
			_rides[n] = _ride_of(n)
	for n in _rides:
		var i: int = _rides[n]
		if i < 0:
			continue
		var d: Vector3 = moved[i]
		(n as Node3D).position += d
		if n == ship:
			ship._land_from.origin += d   # (a landing or take-off under way: its ends move too)
			ship._land_to.origin += d
	_sun_t -= step
	if _sun_t <= 0.0:
		_sun_t = 0.5
		for p: CosmosPlanet in planets:
			p.set_sun((star.global_position - p.global_position).normalized())


## Every world's place now (m, round the star) - for place_now.
func places_now() -> Dictionary:
	return planet_places(system_id, Galaxy.time)


var _body_i := {}                # node -> its index in _bodies (place_now)

## Where `n` is at this moment of the galaxy's clock (m, round the star) -
## between _orbit_tick's steps (30 a second): a world, or what co-orbits one,
## worked out from Galaxy.time; what rides one (you, your ship, a ship near a
## station) moved on by as much as its body has moved since its last step.
## The solar map draws from it each frame: smooth, not 30 steps a second.
## `where`: places_now().
func place_now(n: Node3D, where: Dictionary) -> Vector3:
	var at := n.global_position + origin
	if _bodies.is_empty():
		return at
	if _body_i.size() != _bodies.size():
		_body_i = {}
		for i in _bodies.size():
			_body_i[_bodies[i][0]] = i
	var top: Node = n   # (the world's child it's in: a walker in a ship rides with the ship)
	while top.get_parent() != null and top.get_parent() != world:
		top = top.get_parent()
	var i: int = _body_i.get(top, -1)
	var own := i >= 0
	if not own:
		i = _rides.get(top, -1)
		if i < 0:
			return at
	var b: Array = _bodies[i]
	var bn: Node3D = b[0]
	if not is_instance_valid(bn):
		return at
	var key: String = b[1]
	var now: Vector3 = where.get(key.substr(7), bn.position + origin) if key.begins_with("planet:") else co_orbit(system_id, key, b[2], b[3], Galaxy.time, where)
	return at + now - (bn.position + origin)


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
	if _place_ship_left():
		return
	var at := Vector3(0, 0, 60000)
	var face := Vector3.ZERO
	var saved: Array = CosmosGame.state.get("ship", {}).get("position", [])
	if CosmosGame.from_save and not _placed_from_save and arrive_from == "" and saved.size() == 2:
		# (where the save left you - the 2D game's map units)
		_placed_from_save = true
		at = _clear_of_planets(Vector3(float(saved[0]), 0, float(saved[1])) * PlanetShape.PX_TO_M - origin, 1500.0)
		face = (stations[0].position if not stations.is_empty() else star.position)
		ship.position = at
		if face.distance_to(at) > 1.0:
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
	var look := face if face != Vector3.ZERO else Vector3.ZERO
	if look.distance_to(at) > 1.0:   # (arriving at the origin itself: nothing to face)
		ship.look_at(look, Vector3.UP)
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

var _ship_parts := false




func _process(delta: float) -> void:
	if not built or get_tree().paused:
		return
	if not _ship_parts and ship and CosmosGame.has_ship():
		_ship_parts = ship.parts_in()   # (your ship's hull and rooms put in as their workers finish - started now if they weren't)
	_orbit_tick(delta)
	_shift_origin()
	_deposits_here()
	# (the shadows' reach: short on foot - more detail, far fewer casters - longer flying)
	light.directional_shadow_max_distance = 140.0 if walker else (450.0 if planet_below(ship.global_position, 300.0) else 900.0)
	var mode := DirectionalLight3D.SHADOW_ORTHOGONAL if walker else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	if light.directional_shadow_mode != mode:
		light.directional_shadow_mode = mode
	var ld := (focus().global_position - star.global_position).normalized()
	var inside_ship: bool = walker != null and walker.deck == ship.interior
	var hall := docked or in_port()   # (in a port's hall - docked, coming down its lift, aboard a trader there: its own lights, always)
	ship.interior.set_lit(inside_ship)
	if inside_ship:
		ld = (-ship.global_basis.y + ship.global_basis.x * 0.2).normalized()   # (inside the ship: its ceiling's lights)
	elif hall and hangar:
		ld = (-hangar.global_basis.y + hangar.global_basis.x * 0.3 + hangar.global_basis.z * 0.2).normalized()   # (the hangar's lights: from overhead)
	# (on a planet's night side the sun is behind it: the light fades out)
	var day := 1.0
	var lp := life_planet() if walker or ship.state != "fly" else planet_below(ship.global_position, 3000.0)
	if lp and not hall and not inside_ship:
		var up := (focus().global_position - lp.global_position).normalized()
		day = smoothstep(-0.12, 0.12, up.dot(lp.sun_dir))
	light.light_energy = lerpf(0.04, 1.0, day) if not inside_ship else 0.9
	# (under the weather: the sun dimmed through its clouds - a storm's gloom)
	var wnow: Dictionary = weather_fx.now if weather_fx else {}
	var overcast := float(wnow.get("cover", 0.0)) * (1.0 - smoothstep(300.0, 1500.0, float(wnow.get("alt", 0.0))))
	if not inside_ship and not hall:
		light.light_energy *= 1.0 - 0.6 * overcast - 0.2 * float(wnow.get("storm", 0.0))
	# (the sun low, seen through the air: its light golden, orange, red - dawn and dusk)
	var dusk := 0.0
	if lp and not hall and not inside_ship and lp.atmo_radius > lp.radius:
		var up0 := (focus().global_position - lp.global_position)
		var near0 := 1.0 - smoothstep(0.2, 1.0, (up0.length() - lp.radius) / (lp.atmo_radius - lp.radius))
		dusk = (1.0 - smoothstep(0.0, 0.4, up0.normalized().dot(lp.sun_dir))) * near0
	var sun_col := Color(1.0, 0.97, 0.93).lerp(Color(1.0, 0.52, 0.28), dusk)
	if not light.light_color.is_equal_approx(sun_col):
		light.light_color = sun_col
	light.shadow_enabled = not inside_ship and not hall   # (the hull would shade it all; in a port, its roof)
	_god_rays(lp, wnow, inside_ship or hall)
	var below := dungeon != null
	if light.visible == below:
		light.visible = not below   # (in a dungeon: no sun - nor its shadow maps; the torches light it)
		_surface_shown(not below)
		star.visible = not below
	var shells_on := not hall   # (in your ship too: the sky through its ramp and canopy - the air stops at its hull, the depth buffer's)
	if shells_on != _shells_on:
		_shells_on = shells_on   # (docked: no atmosphere or clouds drawn through the hangar)
		for p: CosmosPlanet in planets:
			for n in ["Atmosphere", "Clouds", "CloudsLow", "CloudsHigh"]:
				var sh := p.get_node_or_null(n)
				if sh:
					sh.visible = shells_on
	if _env:
		var amb := AMBIENT_IN if inside_ship else (AMBIENT_HALL if hall and hangar else AMBIENT_OUT)
		if not inside_ship and not hall and (below or _under_ground()):
			amb = AMBIENT_UNDER
		elif lp and not inside_ship and not hall:
			# (near the ground by night: the stars' and moons' light, dim and cool; under a
			# sky by day the shade is lit by it - the ambient brightens with the daylight,
			# both fading out as you climb away)
			var alt := (focus().global_position - lp.global_position).length() - lp.radius
			var air := lp.atmo_radius > lp.radius
			var near := 1.0 - smoothstep(0.2, 1.0, alt / ((lp.atmo_radius - lp.radius) if air else 1500.0))
			var night := AMBIENT_OUT.lerp(AMBIENT_NIGHT, near * (1.0 if air else 0.6))
			amb = night.lerp(AMBIENT_SKY, day * near) if air else night.lerp(AMBIENT_OUT, day)
			if air:   # (twilight: the sky's light in the shade warm and rosy)
				var e := (focus().global_position - lp.global_position).normalized().dot(lp.sun_dir)
				amb = amb.lerp(AMBIENT_DUSK, exp(-pow((e - 0.03) / 0.16, 2.0)) * near * 0.7)
		if overcast > 0.0 and not inside_ship and not hall and not below:   # (overcast: the light in the shade even, grey)
			amb = amb.lerp(Color(0.3, 0.32, 0.35) * (0.5 + 0.5 * day), overcast * 0.6)
		_weather_fog(wnow, inside_ship or hall or below)
		if not _env.ambient_light_color.is_equal_approx(amb):
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
	_npc_boarding()
	_recalling(delta)
	_docking(delta)
	_ship_calling(delta)
	_huds_for_menus()
	_indoor_light()
	_life_t += delta
	if _life_t >= 0.5:
		_life_t = 0.0
		CosmosWarm.tick_loads()   # (the later background loads asked for and taken in)
		EmpireHulls.pump()   # (a browser: the ships' designs, one at a time)
		_life()
		_towns_tick()
		_lairs_tick()
	for list in _towns.values():
		for t in list:
			if t != null and not t.built:
				t.poll()
	_traffic_t += delta
	_pirate_cd -= delta
	if _traffic_t >= 1.0:
		_traffic_t = 0.0
		_traffic()


func _update_lod(visit: bool) -> void:
	# (meshes from built patches: a frame's budget of them - flying fast the ground must keep up; on foot
	# or slow it comes in a little at a time, no frame much longer than the rest)
	var fast := ship.speed() > 60.0 and walker == null
	CosmosPlanet.deadline_us = Time.get_ticks_usec() + (CosmosPlanet.MESH_BUDGET_US if fast else CosmosPlanet.MESH_BUDGET_SLOW_US)
	CosmosPlanet.visit_budget_us = CosmosPlanet.VISIT_BUDGET_US if fast else CosmosPlanet.VISIT_BUDGET_SLOW_US
	var eye := cam.global_position if cam else ship.global_position
	for p: CosmosPlanet in planets:
		var local := eye - p.global_position
		# (a far planet stays as it is - a few coarse patches: only those near are visited)
		if dungeon != null and p.settled():
			p.collect_only()   # (in a dungeon: the ground overhead unseen - not refined meanwhile)
		elif p.visiting() or (visit and (local.length() < p.radius * 25.0 or not p.settled() or p.deepest_hint > 1)):
			p.update_lod(local)   # (a visit begun goes on, a slice a frame, till it's done)
		else:
			p.collect_only()


## The camera in the open port's hall (its floor to its ceiling, within its rooms
## and halls): lit by the port's own lights whether you're docked yet or not -
## coming down the lift, aboard a trader in it, walking it.
func in_port() -> bool:
	if hangar == null or not is_instance_valid(hangar) or cam == null:
		return false
	if not _dock.is_empty() and int(_dock["phase"]) in [2, 5] and dock_station == hangar.station:
		return true   # (your ship on the lift, down into the hall or up out of it: lit all the way)
	var r := riding()
	if r and r._pad_phase == 3 and r.dest == hangar.station:
		return true   # (aboard a trader on its lift, the camera up the shaft behind it)
	if walker and walker.deck != null and is_instance_valid(walker.deck):
		var wp: Vector3 = hangar.to_local(walker.global_position)
		if wp.y > -3.0 and wp.y < CosmosHangar.HALL_H - 2.0:   # (you down in its hall: lit, however high the camera's up its shafts)
			var wc: Vector3 = hangar.inside(wp, 0.0)
			if Vector2(wc.x - wp.x, wc.z - wp.z).length() < 6.0:
				return true
	var p: Vector3 = hangar.to_local(cam.global_position)
	if p.y < -3.0 or p.y > CosmosHangar.HALL_H + 8.0:   # (the top of its lift shaft too: coming down - not the open pad over it)
		return false
	var c: Vector3 = hangar.inside(p, 0.0)
	return Vector2(c.x - p.x, c.z - p.z).length() < 6.0


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
	for m in monsters:
		if is_instance_valid(m):
			m.lair -= off
	if ship:
		ship._land_from.origin -= off   # (a landing or take-off under way: its ends move too)
		ship._land_to.origin -= off


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
		# Low over the ground: the trees, the boulders and the towns' buildings are solid
		# (the hull's nose, middle, tail and wingtips - balls of HULL_BALL m).
		if r < pl.radius + pl.ground_at(local) + 90.0:
			var fw := -s.global_basis.z
			var sd := s.global_basis.x
			var pts := [p, p + fw * 18.0, p - fw * 16.0, p + sd * 12.0, p - sd * 12.0]
			var rocks := pl.rocks_near(local, 30.0, "ship")
			for pt: Vector3 in pts:
				var lp := pt - pl.global_position
				for rk in rocks:
					var c: Vector3 = rk[0]
					var v := lp - c
					var cu := c.normalized()
					var hgt := v.dot(cu)
					if hgt < -1.0 or hgt > float(rk[2]) + HULL_BALL:
						continue
					var flat := v - cu * hgt
					var need := float(rk[1]) + HULL_BALL
					if flat.length() < need and flat.length() > 0.001:
						_ship_push(s, flat / flat.length() * (need - flat.length()))
				var t := town_at(pl, pt)
				if t:
					var pb := t.push_ball(t.to_local(pt), HULL_BALL)
					if pb != Vector3.ZERO:
						_ship_push(s, t.global_basis * pb)
				if builds and builds.planet == pl:
					var bb := builds.push_ball(pt, HULL_BALL)
					if bb != Vector3.ZERO:
						_ship_push(s, bb)
	for st: CosmosStation in stations:
		if p.distance_to(st.global_position) > st.reach + 1500.0:
			continue
		var f := -s.global_basis.z
		for k in [-1.0, 0.0, 1.0]:
			var push := st.push_out(s.global_position + f * (k * 18.0), 7.0)
			if push != Vector3.ZERO:
				_ship_push(s, push)
	for f: CosmosRocks in fields:
		var lp := p - f.global_position
		if lp.length() > CosmosRocks.SPREAD * 2.5:
			continue
		for rk in f.rocks:
			_push(s, f.global_position + rk[0], rk[1] * 0.9 + CosmosShip.HULL_R * 0.6)
	if star:
		_push(s, star.global_position, star.radius * 1.12)


const HULL_BALL := 4.0          # m: the ship's hull balls against trees and buildings


## The ship moved out of something solid by `push`: its speed into it taken
## away - and a crash (faster than 40 m/s into it) hurts.
func _ship_push(s: CosmosShip, push: Vector3) -> void:
	s.global_position += push
	var n := push.normalized()
	var vn := s.velocity.dot(n)
	if vn < 0.0:
		if vn < -40.0:
			s.hurt(-vn * 0.5)
		s.velocity -= n * vn
		s.velocity *= 0.98
	if s.cruise != 0:
		s.cruise = 0


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
	if walker and walker.planet and dungeon == null and walker.planet.shape.carved_near(pivot - walker.planet.global_position):
		# (dug ground: the camera stops short of a tunnel's or a pit's walls)
		var pl: CosmosPlanet = walker.planet
		var s := 0.25
		while s < t:
			if pl.shape.density(pivot + dir * s - pl.global_position) < 0.25:
				t = maxf(s - 0.3, 0.2)
				break
			s += 0.25
	for n in get_tree().get_nodes_in_group("cam_solid"):
		var n3 := n as Node3D
		if n3 == null or n3 == skip or not n3.is_visible_in_tree():
			continue
		if walker and is_instance_valid(walker.deck) and walker.deck is CosmosNpcInterior and n3 == (walker.deck as CosmosNpcInterior).ship:
			continue   # (aboard it: its rooms keep the camera in, not its hull)
		var reach: float = float(n3.get_meta("cam_reach", 600.0))
		if n3.global_position.distance_to(pivot) > reach + L:
			continue
		if n3.has_method("cam_hit"):   # (its own parts: a station)
			t = minf(t, n3.cam_hit(pivot, dir, t))
			continue
		if not n3.has_meta("cam_parts"):
			var parts: Array = []
			for mi in n3.find_children("*", "MeshInstance3D", true, false):
				if (mi as MeshInstance3D).material_override is StandardMaterial3D and mi.mesh:
					var box: AABB = mi.mesh.get_aabb()
					parts.append([mi, box.get_center(), box.size.length() * 0.5])
			n3.set_meta("cam_parts", parts)
		for part: Array in n3.get_meta("cam_parts"):
			if not is_instance_valid(part[0]):
				continue   # (a part since gone - not typed until it's known to be there)
			var mi: MeshInstance3D = part[0]
			if not mi.is_visible_in_tree():
				continue
			if (mi.global_transform * (part[1] as Vector3)).distance_to(pivot) > float(part[2]) + t:
				continue
			var hit := _seg_box(mi, pivot, dir, t)
			if hit < t:
				t = hit
	# Trunks and boulders (vertical cylinders), and the ground, sampled along.
	var pl := planet_below(pivot, 80.0)
	if pl:
		var local0 := pivot - pl.global_position
		var rocks := pl.rocks_near(local0, L + 2.0, "cam")
		var steps := clampi(ceili(L / 1.2), 3, 10)   # (a sample every ~1.2 m along it: on foot a few, not ten)
		for i in range(1, steps + 1):
			var d := t * i / steps
			var p := pivot + dir * d
			var lp := p - pl.global_position
			var up := lp.normalized()
			if lp.length() < pl.radius + pl.ground_at(lp) + 0.35 and not pl.shape.carved_near(lp):   # (dug ground - a cave, a tunnel: its rock's own, above)
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
	if walker and is_instance_valid(walker.deck) and (walker.deck == ship.interior or walker.deck is CosmosNpcInterior) and cam and cam.walker != null:
		var d: Node3D = walker.deck
		var l := d.to_local(p)
		var c: Vector3 = d.confine(l, 0.25)
		c.y = clampf(l.y, float(d.floor_y(c)) + 0.3, float(d.ceiling_y(c)) - 0.2)
		return d.to_global(c)
	if docked and hangar:
		return hangar.to_global(hangar.inside(hangar.to_local(p), maxf(m, 0.8)))
	for pl: CosmosPlanet in planets:
		var local := p - pl.global_position
		var r := local.length()
		if r > pl.radius + pl.shape.top() + m + 10.0:
			continue
		if pl.shape.carved_near(local):
			if dungeon != null and dungeon.planet == pl:
				return p   # (in a dungeon: its walls and roof keep the camera in - camera_clear)
			return pl.global_position + pl.shape.push_out(local, m)   # (dug ground: out of its walls - into a pit, a tunnel)
		var under := walker != null and walker.diving and walker.planet == pl   # (diving: the camera goes under the sea with you - down to its floor)
		var g := pl.radius + (pl.shape.height(local / r) if under else pl.ground_at(local)) + m
		if r < g:
			return pl.global_position + local / r * g
	return p


func bodies() -> Array:
	var out: Array = [star]
	out.append_array(planets)
	out.append_array(stations)
	out.append_array(gates)
	if walker and ship.visible:
		out.append(ship)
	for x in npc_ships:
		if is_instance_valid(x) and not x.dead and x.global_position.distance_to(focus().global_position) < 20000.0:
			out.append(x)
	for lr in lairs:
		if is_instance_valid(lr) and not is_instance_valid(lr.monster):
			out.append(lr)
	for m in monsters:
		if is_instance_valid(m) and not m.dead and m.global_position.distance_to(focus().global_position) < 30000.0:
			out.append(m)
	if mining and is_instance_valid(mining.proxy):
		out.append(mining.proxy)   # (the rock you're mining)
	for list in _towns.values():   # (the towns of the planet you're near)
		for t in list:
			if t != null and is_instance_valid(t):
				out.append(t)
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
	if b is CosmosTown:
		return b.title()
	if b is CosmosLair:
		return b.title()
	if b is CosmosMonster:
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
	if b is CosmosNpcShip or b is CosmosMonster:
		return b.reach
	if b.has_meta("rock_radius"):
		return float(b.get_meta("rock_radius"))
	return 0.0


func system_title() -> String:
	var sys: Dictionary = Galaxy.system(system_id)
	return "%s system - %s" % [sys.get("name", system_id), Galaxy.empire_name(str(sys.get("owner", "")))]


## The nearest planet, and how high over its ground (the HUD's line).
func where_text() -> String:
	if walker and walker.deck == ship.interior:
		return "Aboard your ship" + ("" if ship.state == "landed" else " - in flight")
	if walker and dungeon:
		return "Below %s - in %s" % [dungeon.planet.rec.get("name", ""), dungeon.site.get("name", "the dark")]
	if walker and walker.deck is CosmosNpcInterior:
		var inn := walker.deck as CosmosNpcInterior
		var r: Dictionary = Galaxy.traders.get(str(inn.ship.get("rec_id")), {})
		var who: String = ("the " + str(r["name"])) if r.has("name") else str(inn.ship.get("label")).to_lower()
		return "Aboard %s - %s" % [who, inn.room_at(inn.to_local(walker.global_position))]
	if walker and walker.deck and port_station():
		return "In the hangar of %s" % label_of(port_station())
	if walker:
		var t0: Dictionary = Planets.TYPES.get(str(walker.planet.rec.get("type", "")), {})
		return "On foot on %s (%s)%s" % [walker.planet.rec.get("name", ""), t0.get("label", "planet"), " - diving" if walker.diving else (" - swimming" if walker.swimming else "")]
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
	if walker == null and mining:   # (an asteroid under the sights: it, to mine and scan)
		var h: Array = mining.rock_under(cam.global_position, fwd, CosmosMining.SCAN_REACH)
		if not h.is_empty() and not (is_instance_valid(mining.proxy) and target == mining.proxy and mining.field == h[0] and mining.rock == h[1]):
			mining.lock(h[0], h[1])
			return
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
const HEAT_FROM := 2.5
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

## The planet (or moon) nearest `p` - its ground's distance - or null.
func nearest_planet(p: Vector3) -> CosmosPlanet:
	var best: CosmosPlanet = null
	var bd := INF
	for pl: CosmosPlanet in planets:
		var d := pl.global_position.distance_to(p) - pl.radius
		if d < bd:
			bd = d
			best = pl
	return best


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
	return "" if not land_spot(pl).is_empty() else _spot_why(pl, (ship.global_position - pl.global_position).normalized(), _ship_fwd(pl))


## The ground a ship sets down on at `u`: the land, or an ice sheet over a sea.
static func set_down_h(pl: CosmosPlanet, u: Vector3) -> float:
	var h := pl.shape.height(u)
	return maxf(h, 0.0) if pl.shape.sea == 2 else h


func _ship_fwd(pl: CosmosPlanet) -> Vector3:
	var u := (ship.global_position - pl.global_position).normalized()
	var f := -ship.global_basis.z
	f = (f - u * f.dot(u))
	return f.normalized() if f.length() > 0.1 else u.cross(Vector3.RIGHT if absf(u.x) < 0.9 else Vector3.UP).normalized()


## Why the ship can't set down at `u` facing `fwd` ("" if it can): water,
## lava, ground too steep under its hull, too uneven under its tail for the
## ramp, trees or boulders.
func _spot_why(pl: CosmosPlanet, u: Vector3, fwd: Vector3) -> String:
	var h := set_down_h(pl, u)
	if pl.shape.sea == 1 and h < 0.6:
		return "water below - find dry land"
	if pl.shape.sea == 3 and h < 0.6:
		return "lava below"
	# Level enough under its hull (the legs' reach: 10 m round its middle).
	var t1 := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := u.cross(t1)
	var lo := h
	var hi := h
	for o in [t1, -t1, t2, -t2]:
		var hh := set_down_h(pl, (u * pl.radius + o * 10.0).normalized())
		lo = minf(lo, hh)
		hi = maxf(hi, hh)
	if hi - lo > 3.5:
		return "too steep here"
	var f := (fwd - u * fwd.dot(u)).normalized()
	var test_spot := Transform3D(Basis.looking_at(f, u), pl.global_position + u * (pl.radius + h + CosmosShip.GEAR))
	var ry := ramp_ground(pl, test_spot)
	if ry < -CosmosShip.GEAR - 2.6 or ry > CosmosShipInterior.FLOOR - 0.25:
		return "the ground under the tail is too uneven for the ramp"
	for rk in pl.rocks_near(u * pl.radius, 24.0):
		if float(rk[2]) > 1.0:
			return "trees or boulders in the way"
	return ""


## Where the ship would set down from here (L): right under it if it can,
## else the nearest good ground within 150 m (rings round it, turned either
## way) - {spot: Transform3D} or {} if there's none. Kept a moment (the HUD
## asks every frame): found again when the ship has moved or after 0.3 s.
var _land_cache := {}

func land_spot(pl: CosmosPlanet) -> Dictionary:
	var now := Time.get_ticks_msec()
	if not _land_cache.is_empty() and _land_cache["pl"] == pl and now - int(_land_cache["t"]) < 300 \
			and (_land_cache["at"] as Vector3).distance_to(ship.global_position - pl.global_position) < 6.0:
		return _land_cache["out"]
	var local := ship.global_position - pl.global_position
	var u := local.normalized()
	var fwd := _ship_fwd(pl)
	var out := {}
	if _spot_why(pl, u, fwd) == "":
		out = {"spot": _spot_at(pl, u, fwd)}
	else:
		var e := fwd
		for ring in [15.0, 30.0, 50.0, 75.0, 110.0, 150.0]:
			for k in 12:
				var d: Vector3 = (u * pl.radius + e.rotated(u, TAU * k / 12.0) * ring).normalized()
				for f in [fwd, -fwd]:
					if _spot_why(pl, d, f) == "":
						out = {"spot": _spot_at(pl, d, f)}
						break
				if not out.is_empty():
					break
			if not out.is_empty():
				break
	_land_cache = {"pl": pl, "t": now, "at": local, "out": out}
	return out


func _spot_at(pl: CosmosPlanet, u: Vector3, fwd: Vector3) -> Transform3D:
	var f := (fwd - u * fwd.dot(u)).normalized()
	return Transform3D(Basis.looking_at(f, u), pl.global_position + u * (pl.radius + set_down_h(pl, u) + CosmosShip.GEAR))


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
	var spot: Transform3D = land_spot(pl)["spot"]   # (under the ship, or the nearest good ground)
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
		hud.flash("Up from the seat - the ship flies on. Click at the seat: back to the controls")


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
	note_event("at_controls")
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


## Up a trader's ramp into its insides (CosmosNpcInterior) from the port's
## floor, and down it again - and aboard it wherever it goes: off its pad, across
## the system, through the gates; the port under whatever pad it goes down on
## opened for you to walk out into. Your ship stays where you left it.
func _npc_boarding() -> void:
	if walker == null:
		return
	if typeof(walker.deck) == TYPE_OBJECT and not is_instance_valid(walker.deck):   # (the deck under you gone - never left standing on nothing)
		walker.seat = {}
		passenger_view(false)
		_lost_aboard()
		return
	if _passenger and (walker.seat.is_empty() or not walker.deck is CosmosNpcInterior):
		passenger_view(false)   # (up from the seat: your own eyes again)
	if walker.deck is CosmosNpcInterior:
		var inn := walker.deck as CosmosNpcInterior
		if not is_instance_valid(inn) or not is_instance_valid(inn.ship) or inn.ship.dead:
			passenger_view(false)
			_lost_aboard()
			return
		var s: CosmosNpcShip = inn.ship
		if s._pad_phase == 3 and s.dest is CosmosStation and not s.pad.is_empty():
			var p := int(s.pad.get("platform", 0))
			if hangar == null or not is_instance_valid(hangar) or hangar.station != s.dest or hangar.platform != p:
				_open_port(s.dest, s.pad)   # (going down into a port: it's there to walk out into)
		var l := inn.to_local(walker.global_position)
		if s.hire_open() and l.z > inn.foot.z - 0.3 and walker.velocity.dot(inn.global_basis.z) > 0.2:   # (a hired ride, down on a field: off onto the ground)
			var hpl: CosmosPlanet = s.hire["pl"]
			walker.set_deck(null)
			walker.planet = hpl
			hud.flash("Down the ramp onto %s" % hpl.rec.get("name", ""))
			note_event("ride_done" if s.hire_state() == "landed" else "ride_left")
			return
		if s._ramp_k > 0.99 and s._pad_phase == 3 and hangar and is_instance_valid(hangar) and hangar.station == s.dest \
				and l.z > inn.foot.z - 0.3 and walker.velocity.dot(inn.global_basis.z) > 0.2:
			walker.set_deck(hangar)
			hud.flash("Down the ramp into the port of %s" % label_of(hangar.station))
		return
	if walker.deck == null and walker.planet:   # (on a world's ground: a hired ride down on its field, its ramp down)
		for x in npc_ships:
			if not is_instance_valid(x) or not x.hire_open() or walker.global_position.distance_to(x.global_position) > x.reach * 2.5 + 20.0:
				continue
			var inn: CosmosNpcInterior = x.make_interior()
			if inn == null or not inn.ok:
				continue
			if _steps_aboard(inn, x):
				walker.set_deck(inn)
				hud.flash("Up the ramp of the local pilot's ship - it lifts off once you're in and he's at the controls")
				note_event("ride_boarded")
				return
		return
	if hangar == null or not is_instance_valid(hangar) or walker.deck != hangar:
		return
	for x in npc_ships:
		if not is_instance_valid(x) or x._pad_phase != 3 or x._ramp_k < 0.99 or x.dest != hangar.station or int(x.pad.get("platform", -1)) != hangar.platform:
			continue
		if walker.global_position.distance_to(x.global_position) > x.reach * 2.5 + 20.0:
			continue
		var inn: CosmosNpcInterior = x.make_interior()   # (near it: its insides made, on a worker)
		if inn == null or not inn.ok:
			continue
		if _steps_aboard(inn, x):
			walker.set_deck(inn)
			var r: Dictionary = Galaxy.traders.get(str(x.rec_id), {})
			hud.flash("Up the ramp of the %s - aboard, it takes you where it goes" % r.get("name", "trader"))
			return


## Onto a ship's ramp from the ground or a port's floor: over it and no lower than a
## step under its top face - walking up at its foot, or standing on it once a little way up.
func _steps_aboard(inn: CosmosNpcInterior, x: CosmosNpcShip) -> bool:
	var l := inn.to_local(walker.global_position)
	if not inn.steps_on(l):
		return false
	return walker.velocity.dot(x.global_basis.z) < -0.2 or l.z < inn.foot.z - 0.6   # (not on the way off it)


## Off a ship, its ramp and legs are solid: the ramp's sides where it stands higher
## than a step (stepped onto where it's low: _npc_boarding), each leg's foot.
func _npc_bumps(w: CosmosWalker) -> void:
	for x: CosmosNpcShip in npc_ships:
		if not is_instance_valid(x) or x._gear.is_empty() or w.global_position.distance_to(x.global_position) > x.reach * 2.5 + 20.0:
			continue
		if x._gear_k > 0.5:
			for g in x._gear:
				var foot: Node3D = g[2]
				var d := w.global_position - foot.global_position
				d -= x.global_basis.y * d.dot(x.global_basis.y)
				var need := foot.scale.x * 0.5 + CosmosWalker.BODY_R
				if d.length() < need and d.length() > 0.01:
					w.global_position += d.normalized() * (need - d.length())
		var inn: CosmosNpcInterior = x.interior
		if inn == null or not inn.ok or x._ramp_k < 0.3:
			continue
		var l := inn.to_local(w.global_position)
		var hw := inn.ramp_hw + CosmosWalker.BODY_R
		if absf(l.x) >= hw or l.z < inn.z_aft - 0.5 or l.z > inn.foot.z + 0.3:
			continue
		var f := inn.floor_y(Vector3(0, 0, clampf(l.z, inn.z_aft, inn.foot.z)))
		if l.y > f - 0.7 or l.y + 1.9 < f - 1.0:
			continue   # (on it, about to step on - or well under its high end)
		l.x = hw * (1.0 if l.x >= 0.0 else -1.0)   # (out to its nearer side)
		w.global_position = inn.to_global(l)


## In a trader's passenger seat: the camera outside it - its whole ship, turned
## round and zoomed as your own ship's is (right button, wheel); yours to watch, not to fly.
var _passenger := false


func passenger_view(on: bool) -> void:
	var s := riding()
	if on and s:
		_passenger = true
		cam.walker = null
		cam.target = s
		cam.zoom = clampf(s.reach / 22.0, 1.0, 6.0) * 1.35
		cam.set_meta("zoom_home", cam.zoom)   # (a middle click comes back to this, the ship's own)
		cam.zoom_max = maxf(4.0, cam.zoom * 3.0)
		cam._q = s.global_basis.get_rotation_quaternion()
		cam.free_look = true   # (the mouse turns the view round the ship, as on foot)
		hud.flash("In the passenger seat - the %s from outside" % Galaxy.traders.get(str(s.rec_id), {}).get("name", "ship"))
	elif _passenger:
		_passenger = false
		cam.target = ship
		cam.zoom = 1.35
		cam.remove_meta("zoom_home")
		cam.zoom_max = 4.0
		cam.free_look = false
		cam._look = Vector2.ZERO
		if walker:
			cam.walker = walker


## The trader you're aboard (or null).
func riding() -> CosmosNpcShip:
	if walker and is_instance_valid(walker.deck) and walker.deck is CosmosNpcInterior and is_instance_valid((walker.deck as CosmosNpcInterior).ship):
		return (walker.deck as CosmosNpcInterior).ship as CosmosNpcShip
	return null


## The ship you were aboard destroyed under you.
func _lost_aboard() -> void:
	var at := walker.global_position
	walker.set_deck(null)
	walker.planet = nearest_planet(at)
	walker.global_position = at
	walker.hurt(walker.hp + 1.0)


## The station whose port you're in (or your ship's, docked).
func port_station() -> CosmosStation:
	if hangar and is_instance_valid(hangar):
		return hangar.station
	return dock_station


## Your ship's in the port you're in (docked under one of its pads).
func ship_in_port(h: CosmosHangar) -> bool:
	return h != null and is_instance_valid(h) and not ship_elsewhere and docked and dock_station == h.station \
		and int(dock_pad.get("platform", -1)) == h.platform


## The second line of the panel on foot, about your ship when it's not with you ("" if it is).
func ship_note() -> String:
	var s := riding()
	if s:
		if s._pad_phase == 3 and s._ramp_k > 0.99:
			return "In port - the ramp's down, aft: off it into the port"
		if not s.hire.is_empty():   # (a hired ride: where you paid to go)
			var to: Dictionary = s.hire["to"]
			return "Bound for %s" % (label_of(to["station"]) if to.has("station") else str((to["pl"] as CosmosPlanet).rec.get("name", "")))
		var d: Node3D = s.dest
		return "Bound for %s" % (label_of(d) if d and not d is CosmosGate else ("the gate to %s" % Galaxy.system((d as CosmosGate).to).get("name", "?") if d is CosmosGate else "its next port"))
	if walker and walker.deck == null and ship_elsewhere:   # (on a world's ground, your ship not here - or none yet)
		return "You have no ship yet - a station's shipyard sells them" if not CosmosGame.has_ship() else "Your ship: %s" % ship_where()
	if walker == null or walker.deck != hangar or hangar == null or ship_in_port(hangar):
		return ""
	if int(_dock.get("phase", -1)) == 2 and dock_station == hangar.station:
		return "Your ship: coming down the lift"
	if not _recall.is_empty():
		return "Your ship: here, waiting for a free pad" if _recall.has("waiting") else "Your ship: on its way to you - %d s" % ceili(float(_recall["t"]))
	if not CosmosGame.has_ship():
		return "You have no ship yet - the shipyard (the services hall) sells them"
	return "Your ship: %s - %s: recall it" % [ship_where(), Keybinds.keys_text("ship_call")]


## Where your ship is, in words.
func ship_where() -> String:
	if not CosmosGame.has_ship():
		return "none yet"
	var at: Dictionary = CosmosGame.extra.get("ship_at", {})
	if ship_elsewhere and not at.is_empty():
		var st: Dictionary = Galaxy.stations.get(str(at.get("station", "")), {})
		return "at %s, %s" % [st.get("name", "a station"), Galaxy.system(str(at.get("system", ""))).get("name", "?")]
	if docked and dock_station:
		return "at %s, pad %d" % [label_of(dock_station), int(dock_pad.get("id", 0))]
	return "out there"


# --- Your ship left behind; recalled ---------------------------------------------------

var ship_elsewhere := false      # (your ship's in another system: here it isn't - nothing of it shown)
var _recall := {}                # {t: s until it's here}


## A ship bought at a station's shipyard when you had none: yours - it comes down this port's lift.
func _bought_first_ship() -> void:
	if CosmosGame.has_ship() or str(CosmosGame.data.ship_class) == "" or int(CosmosGame.data.ship_value) <= 0:
		return
	CosmosGame.extra.erase("no_ship")
	CosmosGame.extra.erase("ship_at")
	ship.apply_upgrades()
	ship.hull = ship.max_hull
	ship.shield = ship.max_shield
	_recall = {"t": 2.0}
	note_event("ship_bought")
	hud.flash("Your first ship is yours - it's coming down this port's lift", 5.0)


## Leaving this system without your ship (aboard a trader through a gate): where it stays.
func _leave_ship_behind() -> void:
	if ship_elsewhere:
		return   # (already somewhere else: still there)
	if docked and dock_station:
		CosmosGame.extra["ship_at"] = {"system": system_id, "station": str(dock_station.record.get("id", "")), "pad": int(dock_pad.get("id", 0))}
	else:
		CosmosGame.extra["ship_at"] = {"system": system_id, "station": str(stations[0].record.get("id", "")) if not stations.is_empty() else "", "pad": -1}


## Your ship as the save left it, if not with you: in another system (not here at
## all), or docked at one of this system's stations. True if it was placed so.
func _place_ship_left() -> bool:
	var at: Dictionary = CosmosGame.extra.get("ship_at", {})
	if not CosmosGame.has_ship():
		at = {"system": ""}   # (none yet: nothing of it anywhere)
	if at.is_empty():
		return false
	if str(at.get("system", "")) != system_id:
		ship_elsewhere = true
		ship.visible = false
		ship.state = "elsewhere"
		ship.control = false
		ship.position = Vector3(0, -1e6, 0)
		return true
	CosmosGame.extra.erase("ship_at")
	var st := _station_by_id(str(at.get("station", "")))
	if st == null:
		return false
	var pd: Dictionary = {}
	for p in st.pads:
		if int(p.get("id", -1)) == int(at.get("pad", -1)):
			pd = p
	if pd.is_empty():
		pd = st.free_pad(CosmosShip.HULL_R * 2.6, st.global_position)
	if pd.is_empty():
		return false
	dock_station = st
	dock_pad = pd
	pd["owner"] = ship
	var xf := st.pad_transform(pd)
	st.lower_pad(pd, LIFT_DEPTH)
	st.set_hatch(pd, 1.0)
	ship.global_transform = Transform3D(_level(pad_nose(xf), xf.basis.y), xf.origin + xf.basis.y * (CosmosShip.GEAR - LIFT_DEPTH))
	ship.state = "landed"
	ship.set_legs(true)
	ship.interior.ramp_end_y = -CosmosShip.GEAR
	ship.velocity = Vector3.ZERO
	docked = true
	return true


## B in a port your ship isn't in: it comes to you - from its pad here, or from
## another system (longer: each jump on the way) - and down this port's lift.
func _recall_ship() -> void:
	if not _recall.is_empty():
		hud.flash("Your ship's on its way - %d s" % ceili(float(_recall["t"])))
		return
	var eta := 25.0
	var at: Dictionary = CosmosGame.extra.get("ship_at", {})
	if ship_elsewhere and not at.is_empty():
		eta = 40.0 + 45.0 * maxf(1.0, float(Galaxy.find_route(str(at.get("system", "")), system_id).size() - 1))   # (each jump on its way)
	elif docked and dock_station:
		eta = 20.0 + dock_station.global_position.distance_to(hangar.station.global_position) / 3000.0
	_recall = {"t": eta}
	hud.flash("Your ship is on its way from %s - about %d s" % [ship_where().trim_prefix("at "), ceili(eta)], 4.0)


func _recalling(delta: float) -> void:
	if _recall.is_empty():
		return
	_recall["t"] = float(_recall["t"]) - delta
	if float(_recall["t"]) > 0.0:
		return
	if walker == null or hangar == null or not is_instance_valid(hangar) or walker.deck != hangar:
		_recall["t"] = 3.0   # (you're not in a port: it waits until you are)
		return
	if ship_in_port(hangar):
		_recall = {}
		return
	var st := hangar.station
	var pd: Dictionary = {}
	for p in st.pads:
		if int(p.get("platform", -1)) == hangar.platform and float(p["size"]) >= CosmosShip.HULL_R * 2.6 \
				and (p.get("owner") == null or not is_instance_valid(p.get("owner")) or p.get("owner") == ship):
			pd = p
	if pd.is_empty():
		_recall["t"] = 5.0   # (every pad of this port's taken: in a moment)
		if not _recall.has("waiting"):
			_recall["waiting"] = true
			hud.flash("Your ship's here - waiting for a pad of this port to come free")
		return
	if docked and dock_station and is_instance_valid(dock_station) and not dock_pad.is_empty():
		dock_station.lower_pad(dock_pad, 0.0)   # (off its old pad: up and away)
		dock_station.set_hatch(dock_pad, 0.0)
		if dock_pad.get("owner") == ship:
			dock_pad["owner"] = null
	docked = false
	ship_elsewhere = false
	CosmosGame.extra.erase("ship_at")
	dock_station = st
	dock_pad = pd
	pd["owner"] = ship
	var xf := st.pad_transform(pd)
	ship.global_transform = Transform3D(_level(pad_nose(xf), xf.basis.y), xf.origin + xf.basis.y * CosmosShip.GEAR)
	ship.visible = true
	ship.state = "landed"
	ship.set_legs(true)
	ship.velocity = Vector3.ZERO
	ship.set_process(true)
	ship.control = false
	_recall = {}
	_dock = {"phase": 2, "t": 0.0, "at": st.to_local(ship.global_position)}   # (down this port's lift)
	hud.flash("Your ship's here - down the lift onto pad %d" % int(pd.get("id", 0)), 4.0)


## Aboard a trader through its gate: the next system, you still aboard it - your ship left behind.
func _ride_through(s: CosmosNpcShip) -> void:
	if _jumping:
		return   # (once: on its way already)
	var to: String = (s.dest as CosmosGate).to if s.dest is CosmosGate else ""
	if to == "" or not Galaxy.systems.has(to):
		return
	_leave_ship_behind()
	CosmosGame.extra["riding"] = s.rec_id
	_recall = {}
	var r: Dictionary = Galaxy.traders.get(s.rec_id, {})
	r["live"] = false
	_flown.erase(s.rec_id)
	Galaxy.leg_done(s.rec_id)
	_jumping = true
	jumped_to = to
	if dry_run:
		return
	arrive_from = ""   # (your ship doesn't come through: you do, aboard)
	Galaxy.current_system = to
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	LoadVeil.change_to(SCENE, "Through the gate to %s - aboard the %s" % [Galaxy.system(to).get("name", to), r.get("name", "trader")])


## Arrived (a gate ridden through, or a save loaded): back aboard the trader you
## were riding, or on foot in the port you were in. The veil waits for it.
var _resuming := false


func _resume_on_foot() -> void:
	var rid := str(CosmosGame.extra.get("riding", ""))
	var foot: Dictionary = CosmosGame.extra.get("foot_at", {})
	var start := str(CosmosGame.extra.get("start", ""))
	var on_pl: Dictionary = CosmosGame.extra.get("on_planet", {})
	if start != "" or not on_pl.is_empty():
		_resuming = true
		CosmosGame.extra.erase("start")
		CosmosGame.extra.erase("on_planet")
		await _set_down_on_world(start if start != "" else str(on_pl.get("planet", "")), on_pl.get("at", []))
		_resuming = false
		return
	if rid == "" and foot.is_empty():
		return
	_resuming = true
	CosmosGame.extra.erase("riding")
	CosmosGame.extra.erase("foot_at")
	if rid != "":
		var s: CosmosNpcShip = null
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 15000:
			_sync_traders()
			if _flown.has(rid) and is_instance_valid(_flown[rid]):
				s = _flown[rid]
				break
			await get_tree().process_frame
		if s:
			s._make_gear()
			var inn := s.make_interior()
			while not inn.built:
				await get_tree().process_frame
			if inn.ok:
				var hold: Array = inn.rooms[inn.rooms.size() - 1]
				_make_walker(inn, inn.to_global(Vector3(0, inn.sill, float(hold[1]) + 2.0)), -s.global_basis.z)
				var r: Dictionary = Galaxy.traders.get(rid, {})
				hud.flash("Aboard the %s - bound for %s" % [r.get("name", "trader"), label_of(s.dest) if s.dest and not s.dest is CosmosGate else "its next port"], 4.0)
				_resuming = false
				return
		foot = {"station": str(stations[0].record.get("id", "")) if not stations.is_empty() else "", "platform": 0}   # (its ship not to be found: set down in a port here)
	var st := _station_by_id(str(foot.get("station", "")))
	if st == null and not stations.is_empty():
		st = stations[0]
	if st:
		var plat := clampi(int(foot.get("platform", 0)), 0, maxi(st.platforms.size() - 1, 0))
		var pd: Dictionary = {}
		for p in st.pads:
			if int(p.get("platform", -1)) == plat:
				pd = p
		_open_port(st, pd if not pd.is_empty() else {"platform": plat})
		while not hangar.built:
			await get_tree().process_frame
		var at := hangar.to_global(Vector3(hangar.xa + 1.0 + CosmosHangar.CONC * 0.5, 0, 0))
		_make_walker(hangar, at, hangar.global_basis.x)
	_resuming = false


## On foot on the world named `planet`: at `at` (planet-local, a save's) or - a new
## game - by its first city's landing field, the city's people beside you.
func _set_down_on_world(pname: String, at: Array) -> void:
	var pl: CosmosPlanet = null
	for p: CosmosPlanet in planets:
		if str(p.rec.get("name", "")) == pname:
			pl = p
	if pl == null:
		for p: CosmosPlanet in planets:
			if not p.towns.is_empty():
				pl = p
				break
	if pl == null:
		return
	var local := Vector3.ZERO
	var face := Vector3.FORWARD
	if at.size() == 3:
		local = Vector3(float(at[0]), float(at[1]), float(at[2]))
	else:
		var site: Dictionary = pl.towns[0]
		for s in pl.towns:
			if str(s.get("kind", "")) == "city":
				site = s
				break
		var field := CosmosSandbox.field_of(pl, site)
		local = field * Vector3(-24.0, 0.0, 4.0)   # (on the field's edge, by the city's people)
		face = field.basis * Vector3(-1, 0, 0)
	var u := local.normalized()
	if walker == null:
		walker = CosmosWalker.new()
		walker.cosmos = self
		world.add_child(walker)
	walker.planet = pl
	walker.set_deck(null)
	walker.global_position = pl.global_position + u * (pl.radius + walker.floor_at(local) + 0.05)
	walker.heading = (face - u * face.dot(u)).normalized()
	walker.facing = walker.heading
	walker.velocity = Vector3.ZERO
	cam.walker = walker
	_gauge_on_walker(true)
	ship.control = false
	_shift_origin(true)
	sandbox.holding(true)   # (a package you had: in your hands again)
	for i in 3:
		await get_tree().process_frame


func _make_walker(deck: Node3D, at: Vector3, face: Vector3) -> void:
	if walker == null:
		walker = CosmosWalker.new()
		walker.cosmos = self
		world.add_child(walker)
	walker.global_position = at
	walker.set_deck(deck)
	walker.heading = face
	walker.facing = face
	cam.walker = walker
	_gauge_on_walker(true)
	ship.control = false
	_shift_origin(true)
	sandbox.holding(true)   # (a package you had: in your hands again)


## Saving: not aboard a moving ship (a moment, until it's down).
func can_save() -> bool:
	return riding() == null


## On foot on a planet: its deposits round you (made for the planet you're
## on; dropped once you've flown off).
func _deposits_here() -> void:
	var pl: CosmosPlanet = walker.planet if walker and walker.get("planet") else null
	if pl and (deposits == null or deposits.planet != pl):
		if deposits:
			deposits.queue_free()
		deposits = CosmosDeposits.new()
		deposits.cosmos = self
		deposits.planet = pl
		pl.add_child(deposits)
	elif deposits and walker == null and ship.state == "fly":
		deposits.queue_free()
		deposits = null


## Keeps the walker out of the landed ship and the boulders.
func walker_bumps(w: CosmosWalker) -> void:
	var u := w.up()
	if w.deck == ship.interior:
		return
	if w.deck == null or w.deck == hangar:
		_npc_bumps(w)
	if (ship.state == "landed" or ship.state == "landing") and ship.interior:
		# (outside: the landing legs are solid; under the hull you walk free - to the ramp)
		for leg: Vector3 in [Vector3(0, 0, -11), Vector3(-6.5, 0, 9), Vector3(6.5, 0, 9)]:
			var d := w.global_position - ship.to_global(leg)
			d -= u * d.dot(u)
			if d.length() < 1.6 and d.length() > 0.01:
				w.global_position += d.normalized() * (1.6 - d.length())
	if w.deck:
		return
	var held_at := w.global_position   # (what holds you out from here on is a wall to climb - not people, not the ship's legs)
	var in_dg := false
	for d: CosmosDungeon in dungeons_live():   # (a dungeon's walls, its roof)
		if d.planet == w.planet:
			var dl := d.to_local(w.global_position)
			if d.inside(dl):
				in_dg = true
				dl += d.push(dl, CosmosWalker.BODY_R)
				var roof: float = d.ceiling_y(dl) - 1.85
				if dl.y > roof:
					dl.y = roof
					if w.velocity.dot(u) > 0.0:
						w.velocity -= u * w.velocity.dot(u)
				w.global_position = d.to_global(dl)
	var town := town_at(w.planet, w.global_position)
	if town:
		w.global_position += town.global_basis * town.push(town.to_local(w.global_position), CosmosWalker.BODY_R)
	if builds:
		builds.push_walker(w)
	if deposits and deposits.planet == w.planet:
		deposits.push(w)
	var lw := w.global_position - w.planet.global_position
	if not in_dg and w.planet.shape.carved_near(lw):
		# (dug ground: kept out of its walls and ceilings - the knees and the head)
		for hgt: float in [0.55, 1.5]:
			var pt: Vector3 = lw + u * hgt
			var mv: Vector3 = w.planet.shape.push_out(pt, CosmosWalker.BODY_R * 0.8) - pt
			lw += mv - u * mv.dot(u)   # (sideways: the floor's the floor's business - floor_at)
		# (under the ground - a tunnel, a cave: its ceiling holds you down - a jump, the jet, swimming up)
		var sh := w.planet.shape
		if lw.length() - w.planet.radius < sh.height(u) - 0.5 and sh.density(lw + u * 1.75) < 0.0:
			for k in 20:
				lw -= u * 0.1
				if sh.density(lw + u * 1.75) >= 0.0:
					break
			if w.velocity.dot(u) > 0.0:
				w.velocity -= u * w.velocity.dot(u)
		w.global_position = w.planet.global_position + lw
	var local := w.global_position - w.planet.global_position
	for rk in w.planet.rocks_near(local, 3.0, "walker"):   # (its last answer while fresh)
		var c: Vector3 = rk[0]
		var d := local - c
		var flat := d - u * d.dot(u)
		var need: float = rk[1] + CosmosWalker.BODY_R
		# (low ones you step over; tall ones block)
		if float(rk[2]) > 0.5 and flat.length() < need and d.dot(u) < float(rk[2]) and flat.length() > 0.001:
			w.global_position += flat.normalized() * (need - flat.length())
	var held := w.global_position - held_at
	w.note_wall(held - u * held.dot(u))
	if underwater and (w.swimming or w.diving):   # (the sea floor's boulders and corals: solid to a diver)
		for rk in underwater.rocks_near(local, 3.0):
			var d: Vector3 = w.global_position - w.planet.global_position - (rk[0] as Vector3)
			var flat := d - u * d.dot(u)
			var need: float = float(rk[1]) + CosmosWalker.BODY_R
			if flat.length() < need and d.dot(u) < float(rk[2]) and flat.length() > 0.001:
				w.global_position += flat.normalized() * (need - flat.length())


# --- Dismissing and recalling the ship ------------------------------------------------

## On foot on a planet, B: your ship, landed and empty, lifts off and climbs
## away out of sight (it waits in orbit); B again calls it back - it comes
## down out of the sky onto a clear, level spot near you (a town's landing
## field when you're in a town) and lowers its ramp.
const CALL_TIME := 8.0          # s: the ship's way down (or up and away)
const CALL_ALT := 700.0         # m: where it comes from / goes to
const PICK_ALT := 120.0         # m: flying free higher than this, B brings it to you (and you aboard)
var ship_away := false
var _call := {}                 # {kind: "up" / "down", t, from (planet-local), to (planet-local Transform3D), pl}


func ship_call() -> void:
	if not CosmosGame.has_ship():
		hud.flash("You have no ship yet - ride with a town's local pilot, or buy one at a station's shipyard")
		return
	if ship_elsewhere and walker and walker.deck != hangar:
		hud.flash("Your ship's %s - recall it from a station's port" % ship_where())
		return
	if walker and hangar and is_instance_valid(hangar) and walker.deck == hangar and not ship_in_port(hangar):
		_recall_ship()   # (in a port your ship isn't in: it comes to you)
		return
	if not _call.is_empty() or walker == null or walker.planet == null:
		return
	var pl: CosmosPlanet = walker.planet
	if walker.deck == null and not walker.on_ground and walker._flying and walker.height_above_ground() > PICK_ALT:
		# (flying free, high up or out in space: it comes to you, and you're aboard)
		if docked or (ship.state == "landed" and not ship_away and ship.global_position.distance_to(walker.global_position) < 60.0):
			return
		var inv := pl.global_transform.affine_inverse()
		var from := inv * ship.global_transform
		if ship_away:
			from = inv * Transform3D(ship.global_basis, walker.global_position + (walker.global_position - pl.global_position).normalized() * CALL_ALT * 2.0)
		ship.interior.set_ramp(false)
		ship.state = "remote"
		ship.set_legs(false)
		ship.visible = true
		_call = {"kind": "pick", "t": 0.0, "from": from, "pl": pl}
		hud.flash("Your ship is coming for you", 3.0)
		note_event("ship_called")
		return
	if not ship_away:
		if ship.state != "landed" or docked:
			hud.flash("Your ship isn't landed")
			return
		ship.interior.set_ramp(false)
		ship.state = "remote"
		ship.set_legs(false)
		var start := pl.global_transform.affine_inverse() * ship.global_transform
		_call = {"kind": "up", "t": 0.0, "from": start, "pl": pl}
		hud.flash("Your ship lifts off - B to call it back", 3.0)
		return
	var spot := _landing_spot_near(pl, walker.global_position - pl.global_position)
	if spot == Transform3D():
		hud.flash("No clear, level ground near you for your ship - move on a little")
		return
	ship.visible = true
	ship.state = "remote"
	_call = {"kind": "down", "t": 0.0, "to": spot, "pl": pl}
	hud.flash("Your ship is on its way down", 3.0)


## A clear, level spot for the ship 30-150 m from planet-local `at` (a town's
## landing field first, if you're in or by a town), as its landed transform
## (planet-local), or Transform3D() if there's none.
func _landing_spot_near(pl: CosmosPlanet, at: Vector3) -> Transform3D:
	var u := at.normalized()
	var t := town_at(pl, pl.global_position + at)
	if t:
		var field: Vector3 = (pl.global_transform.affine_inverse() * t.global_transform) * t.port
		var fu := field.normalized()
		return Transform3D(_level(t.global_basis.x, fu), fu * (pl.radius + set_down_h(pl, fu) + CosmosShip.GEAR))
	var e := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized()
	for ring in [40.0, 70.0, 100.0, 140.0]:
		for k in 10:
			var dir: Vector3 = e.rotated(u, TAU * k / 10.0)
			var d: Vector3 = (at + dir * ring).normalized()
			if pl.shape.cleared(d) and town_at(pl, pl.global_position + d * pl.radius) != null:
				continue
			if _spot_why(pl, d, -dir) == "":
				return _spot_at(pl, d, -dir).translated(-pl.global_position)   # (planet-local; its tail toward you: the ramp)
	return Transform3D()


func _ship_calling(delta: float) -> void:
	if _call.is_empty():
		return
	var pl: CosmosPlanet = _call["pl"]
	if not is_instance_valid(pl):
		_call = {}
		return
	_call["t"] += delta
	var k := minf(float(_call["t"]) / CALL_TIME, 1.0)
	if _call["kind"] == "pick":
		var from: Transform3D = pl.global_transform * (_call["from"] as Transform3D)
		if walker == null:
			_call = {}
			return
		var wu: Vector3 = walker.up()
		var to := walker.global_position - walker.facing * 22.0 - wu * 6.0
		var e := smoothstep(0.0, 1.0, k)
		var b := from.basis.slerp(_level(walker.facing, wu), e).orthonormalized()
		ship.global_transform = Transform3D(b, from.origin.lerp(to, e))
		ship._engines(delta)
		if k >= 1.0:
			_call = {}
			ship.state = "fly"
			ship.velocity = Vector3.ZERO
			ship.throttle = 0.0
			ship_away = false
			embark()
			hud.flash("Aboard - at the controls", 3.0)
		return
	if _call["kind"] == "up":
		var from: Transform3D = _call["from"]
		var up := from.origin.normalized()
		var e := k * k
		ship.global_transform = pl.global_transform * Transform3D(from.basis.rotated(from.basis.x, -0.6 * smoothstep(0.0, 0.4, k)),
			from.origin + up * CALL_ALT * e + (-from.basis.z) * CALL_ALT * 0.6 * e)
		ship._engines(delta)
		if k >= 1.0:
			ship.visible = false
			ship_away = true
			_call = {}
	else:
		var to: Transform3D = _call["to"]
		var up := to.origin.normalized()
		var e := 1.0 - (1.0 - k) * (1.0 - k)
		var pos := to.origin + up * CALL_ALT * (1.0 - e) + (to.basis.z) * CALL_ALT * 0.4 * (1.0 - e)
		ship.global_transform = pl.global_transform * Transform3D(to.basis, pos)
		if k >= 1.0:
			ship.global_transform = pl.global_transform * to
			ship.state = "landed"
			ship.set_legs(true)
			ship._land_to = ship.global_transform
			ship.interior.ramp_end_y = ramp_ground(pl, ship.global_transform)
			ship.interior.set_ramp(true)
			ship_away = false
			_call = {}
			hud.flash("Your ship has landed - its ramp is down")


# --- Caves and dungeons ---------------------------------------------------------------

## A planet's caves and dungeons. Its dungeons: two on a rocky world, where its
## seed puts them on dry, level ground away from the towns - a stone gateway
## with horns, steps going down; E at one goes in (CosmosDungeon: a place of
## its own). Its caves are its ground's own (PlanetShape.caves: tunnels carved
## into a hillside, or into an abyss's wall under the sea) - walked or swum
## straight in, their dead in their chambers, a chest in the deepest
## (_cave_life); a rock arch round a hillside cave's mouth.
var dungeon: CosmosDungeon = null   # (the one you're in - under the ground: no sun, no markers)
var _dungeons := {}              # CosmosPlanet -> [[site, entrance node or null]]
const CAVE_NAMES := ["Cave of Eileithyia", "Idaean Cave", "Dictaean Cave", "Cave of Skotino", "Cave of Melidoni", "Cave of Kamares"]
const ABYSS_NAMES := ["Abyss of Poseidon", "Deeps of Nereus", "Pit of Charybdis", "Abyss of Okeanos", "Hollow of Thetis", "Deep of Proteus"]
const DUNGEON_NAMES := ["Labyrinth of Asterion", "Tomb of Minos", "Crypt of Phaistos", "Halls of the Dead", "Vaults of Hades", "Pit of Tartarus"]


func dungeons_of(pl: CosmosPlanet) -> Array:
	if _dungeons.has(pl):
		return _dungeons[pl]
	var out: Array = []
	if pl.shape.kind == "rocky":
		var di := 0
		for dg: Dictionary in pl.shape.dungeons:
			var m: Vector3 = dg["mouth"]
			out.append([{"dir": m.normalized(), "kind": "dungeon", "seed": int(dg["seed"]), "dungeon": dg,
				"name": DUNGEON_NAMES[(int(pl.rec.get("seed", 1)) + di * 2 + 1) % DUNGEON_NAMES.size()]}, null])
			di += 1
		var ci := 0
		for cave: Dictionary in pl.shape.caves:
			var under := bool(cave["under"])
			var names: Array = ABYSS_NAMES if under else CAVE_NAMES
			var m: Vector3 = cave["mouth"]
			out.append([{"dir": m.normalized(), "kind": "cave", "seed": int(cave["seed"]), "cave": cave, "under": under,
				"name": names[(int(pl.rec.get("seed", 1)) + ci) % names.size()]}, null])
			ci += 1
	if pl.caves_ready:   # (kept once its caves and dungeons are in)
		_dungeons[pl] = out
	return out


## Their mouths, built within 600 m (freed past 900) - called with the life tick.
func _dungeon_mouths(pl: CosmosPlanet, here: Vector3) -> void:
	for e in dungeons_of(pl):
		var site: Dictionary = e[0]
		var at: Vector3 = (site["dir"] as Vector3) * (pl.radius + pl.shape.height(site["dir"]))
		var dist := at.distance_to(here)
		if site.get("under", false):
			continue   # (an abyss's cave: its mouth in the abyss's wall, no arch)
		if dist < 600.0 and e[1] == null:
			e[1] = _build_mouth(pl, site)
		elif dist > 900.0 and e[1] != null:
			(e[1] as Node).queue_free()
			e[1] = null


func _build_mouth(pl: CosmosPlanet, site: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = "CaveMouth" if site["kind"] == "cave" else "DungeonGate"
	n.add_to_group("cam_solid")
	n.set_meta("cam_reach", 15.0)
	pl.add_child(n)   # (on its world: moves with it)
	var u: Vector3 = site["dir"]
	var f := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized()
	var at := u * (pl.radius + pl.shape.height(u))
	var into: Dictionary = site.get("cave", site.get("dungeon", {}))
	if not into.is_empty():   # (round its real opening: facing in along the passage)
		var w: Vector3 = into["way"]
		f = (w - u * w.dot(u)).normalized()
		at = into["mouth"]
	n.global_transform = Transform3D(Basis.looking_at(f, u), pl.global_position + at)
	var stone := CosmosStation._mat(Color(0.45, 0.42, 0.38), 0.0, 0.9)
	var dark := CosmosStation._mat(Color(0.01, 0.01, 0.01), 0.0, 1.0)
	var red := CosmosStation._mat(Color(0.5, 0.1, 0.07), 0.0, 0.8)
	var add := func(mesh: Mesh, mat: Material, at: Vector3, sc := Vector3.ONE) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = at
		mi.scale = sc
		n.add_child(mi)
		return mi
	if site["kind"] == "cave":
		var rock: Mesh = CosmosPlanet.rock_mesh()
		var rm := CosmosStation._mat(Color(0.36, 0.32, 0.28), 0.0, 0.95)
		for k in 7:   # (an arch of boulders round its opening)
			var a := PI * k / 6.0
			add.call(rock, rm, Vector3(cos(a) * 3.6, sin(a) * 3.2 - 0.6, 0.6), Vector3.ONE * (1.6 + 0.4 * sin(k * 2.0)))
	else:
		for sx in [-1.0, 1.0]:
			add.call(CosmosStation._box(Vector3(1.0, 4.2, 1.0)), stone, Vector3(2.0 * sx, 2.1, 0))
		add.call(CosmosStation._box(Vector3(5.4, 0.8, 1.2)), stone, Vector3(0, 4.6, 0))
		for sx in [-1.0, 1.0]:   # (horns of consecration on the lintel)
			add.call(CosmosStation._box(Vector3(0.35, 0.9, 0.35)), red, Vector3(0.7 * sx, 5.45, 0))
		add.call(CosmosStation._box(Vector3(2.2, 0.3, 0.4)), red, Vector3(0, 5.1, 0))
	return n


# (The caves in the ground: their dead and their chest, there while you're near.)
const CAVE_NEAR := 150.0         # m from its mouth or a chamber: its dead wake, its chest's there
var _cave_live := {}             # chest key -> {pl, site, foes: [CosmosNpc], chest: Node3D, at: planet-local chest}


func _cave_life(pl: CosmosPlanet, here: Vector3) -> void:
	for e in dungeons_of(pl):
		var site: Dictionary = e[0]
		if not site.has("cave"):
			continue
		var cave: Dictionary = site["cave"]
		var dmin := (cave["mouth"] as Vector3).distance_to(here)
		for ch in cave["chambers"]:
			dmin = minf(dmin, (ch[0] as Vector3).distance_to(here))
		var key := _chest_key(pl, site)
		if dmin < CAVE_NEAR and not _cave_live.has(key):
			_cave_wake(pl, site, key)
		elif dmin > CAVE_NEAR * 2.0 and _cave_live.has(key):
			_cave_sleep(key)
	for key in _cave_live.keys():   # (another world now)
		if _cave_live[key]["pl"] != pl:
			_cave_sleep(key)


## The floor in a cave at planet-local `p` (in its air): planet-local.
static func cave_floor(pl: CosmosPlanet, p: Vector3) -> Vector3:
	return p.normalized() * (pl.radius + pl.shape.floor_below(p))


## Its dead in its chambers - skeleton warriors, demons deeper in, a demon lord
## by the chest in the deepest - and the chest.
func _cave_wake(pl: CosmosPlanet, site: Dictionary, key: String) -> void:
	var cave: Dictionary = site["cave"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site["seed"]) + 9
	var chambers: Array = cave["chambers"]
	var deepest := int(cave["deepest"])
	var foes: Array = []
	var chest_at := Vector3.ZERO
	for k in chambers.size():
		var c: Vector3 = chambers[k][0]
		var cr: float = chambers[k][1]
		var u := c.normalized()
		var t1 := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized()
		if k == deepest:
			chest_at = cave_floor(pl, c + t1 * cr * 0.3)
		for j in rng.randi_range(1, 2):
			var kind := "demon" if k == deepest and rng.randf() < 0.5 else "skeleton"
			var at := cave_floor(pl, c + t1.rotated(u, rng.randf() * TAU) * cr * 0.4)
			foes.append(_cave_foe(pl, at, kind, rng.randi(), false))
	if not chambers.is_empty():
		foes.append(_cave_foe(pl, cave_floor(pl, (chambers[deepest][0] as Vector3)), "demon", rng.randi(), true))
	var looted: bool = key in CosmosGame.extra.get("looted", [])
	var chest := _cave_chest(pl, chest_at, looted)
	_cave_live[key] = {"pl": pl, "site": site, "foes": foes, "chest": chest, "at": chest_at, "open": looted}


func _cave_sleep(key: String) -> void:
	var e: Dictionary = _cave_live[key]
	for x in e["foes"]:
		if is_instance_valid(x):
			x.queue_free()
	if is_instance_valid(e["chest"]):
		(e["chest"] as Node).queue_free()
	_cave_live.erase(key)


func _cave_foe(pl: CosmosPlanet, at: Vector3, kind: String, seed: int, boss: bool) -> CosmosNpc:
	var npc := CosmosNpc.new()
	npc.cosmos = self
	npc.cave_foe(pl, seed, kind, boss)
	world.add_child(npc)
	npc.global_position = pl.global_position + at
	npcs.append(npc)
	return npc


## A bronze chest on a cave's floor (planet-local `at`), its lid up when it's been opened; a warm glow while it's shut.
func _cave_chest(pl: CosmosPlanet, at: Vector3, open: bool) -> Node3D:
	var n := Node3D.new()
	n.name = "CaveChest"
	pl.add_child(n)
	var u := at.normalized()
	var f := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized()
	n.global_transform = Transform3D(Basis.looking_at(f, u), pl.global_position + at)
	var bronze := CosmosStation._mat(Color(0.55, 0.36, 0.14), 0.85, 0.35)
	var body := MeshInstance3D.new()
	body.mesh = CosmosStation._box(Vector3(1.1, 0.6, 0.7))
	body.material_override = bronze
	body.position = Vector3(0, 0.3, 0)
	n.add_child(body)
	var lid := MeshInstance3D.new()
	lid.name = "Lid"
	lid.mesh = CosmosStation._box(Vector3(1.14, 0.14, 0.74))
	lid.material_override = bronze
	n.add_child(lid)
	_chest_lid(n, open)
	return n


func _chest_lid(n: Node3D, open: bool) -> void:
	var lid := n.get_node("Lid") as Node3D
	lid.transform = Transform3D(Basis(Vector3.RIGHT, -1.9), Vector3(0, 0.62, -0.35) + Basis(Vector3.RIGHT, -1.9) * Vector3(0, 0, 0.37)) if open else Transform3D(Basis(), Vector3(0, 0.67, 0))
	var glow := n.get_node_or_null("Glow")
	if not open and glow == null:
		var l := OmniLight3D.new()
		l.name = "Glow"
		l.light_color = Color(1.0, 0.7, 0.3)
		l.light_energy = 1.2
		l.omni_range = 7.0
		l.shadow_enabled = false
		l.position = Vector3(0, 1.0, 0)
		n.add_child(l)
	elif open and glow:
		glow.queue_free()


## A shut cave chest within reach of you: its _cave_live entry, or {}.
func cave_chest_here() -> Dictionary:
	if walker == null or walker.deck != null:
		return {}
	for key in _cave_live:
		var e: Dictionary = _cave_live[key]
		if not e["open"] and e["pl"] == walker.planet and ((e["pl"] as CosmosPlanet).global_position + (e["at"] as Vector3)).distance_to(walker.global_position) < 2.2:
			return e
	return {}


func open_cave_chest() -> void:
	var e := cave_chest_here()
	if e.is_empty():
		return
	e["open"] = true
	_chest_lid(e["chest"], true)
	_loot(e["pl"], e["site"])


# (The dungeons in the ground: built as you come near - its rooms, its dead, its chest.)
const DUNGEON_NEAR := 260.0      # m from its gateway or its middle: built, its dead in it
var _dungeon_live := {}          # chest key -> {pl, site, node: CosmosDungeon, foes: [], woke: bool}


func _dungeon_life(pl: CosmosPlanet, here: Vector3) -> void:
	for e in dungeons_of(pl):
		var site: Dictionary = e[0]
		if not site.has("dungeon"):
			continue
		var dg: Dictionary = site["dungeon"]
		var dist := minf((dg["mouth"] as Vector3).distance_to(here), (dg["centre"] as Vector3).distance_to(here))
		var key := _chest_key(pl, site)
		if dist < DUNGEON_NEAR and not _dungeon_live.has(key):
			var d := CosmosDungeon.new()
			d.setup(pl, site)
			pl.add_child(d)   # (on its world: in its ground, under its gateway)
			d.transform = dg["frame"]
			_dungeon_live[key] = {"pl": pl, "site": site, "node": d, "foes": [], "woke": false}
		elif dist > DUNGEON_NEAR * 1.7 and _dungeon_live.has(key):
			_dungeon_sleep(key)
	for key in _dungeon_live.keys():
		var e: Dictionary = _dungeon_live[key]
		if e["pl"] != pl:
			_dungeon_sleep(key)
		elif not e["woke"] and (e["node"] as CosmosDungeon).poll():
			e["woke"] = true
			_dungeon_wake(e)


## Its dead: skeletons in the rooms, demons deeper in, the lord by the chest.
func _dungeon_wake(e: Dictionary) -> void:
	var d: CosmosDungeon = e["node"]
	var site: Dictionary = e["site"]
	d.chest_open = _chest_key(e["pl"], site) in CosmosGame.extra.get("looted", [])   # (once, ever: kept in the save)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site["seed"]) + 9
	var deepest := 0
	for r in d.rooms:
		deepest = maxi(deepest, int(r[1]))
	for r in d.rooms:
		var depth := int(r[1])
		if depth == 0:
			continue
		var rect: Rect2 = r[0]
		for k in rng.randi_range(1, 3):
			var kind := "demon" if depth > deepest / 2 and rng.randf() < 0.45 else "skeleton"
			e["foes"].append(_dungeon_foe(d, kind, Vector3(rng.randf_range(rect.position.x + 1.5, rect.end.x - 1.5), 0.0, rng.randf_range(rect.position.y + 1.5, rect.end.y - 1.5)), rng.randi(), false))
	e["foes"].append(_dungeon_foe(d, "demon", d.chest_at + Vector3(0, 0, 2.5), rng.randi(), true))


func _dungeon_sleep(key: String) -> void:
	var e: Dictionary = _dungeon_live[key]
	for x in e["foes"]:
		if is_instance_valid(x):
			x.queue_free()
	if is_instance_valid(e["node"]):
		if dungeon == e["node"]:
			dungeon = null
		(e["node"] as Node).queue_free()
	_dungeon_live.erase(key)


func _dungeon_foe(d: CosmosDungeon, kind: String, at: Vector3, seed: int, boss: bool) -> CosmosNpc:
	var npc := CosmosNpc.new()
	npc.cosmos = self
	npc.foe_of(d, seed, kind, boss)
	world.add_child(npc)
	npc.global_position = d.to_global(at)
	npcs.append(npc)
	return npc


## In a dungeon: the worlds' surfaces (their ground, seas, skies, towns, plants)
## and the star not drawn - out of sight overhead; the dungeon and the carved
## rock (its passage up) are.
func _surface_shown(on: bool) -> void:
	var door := Vector3.INF
	if dungeon and is_instance_valid(dungeon):
		door = dungeon.to_global(dungeon.exit_at)
	for p: CosmosPlanet in planets:
		for ch in p.get_children():
			if ch is CosmosVoxels:   # (the carved rock: only by its doorway - the passage up; the rest behind its walls)
				for mi in ch.get_children():
					if mi is Node3D:
						var keep: bool = on or (mi as Node3D).global_position.distance_to(door) < 24.0
						if (mi as Node3D).visible != keep:
							(mi as Node3D).visible = keep
			elif ch is Node3D and not ch is CosmosDungeon and (ch as Node3D).visible != on:
				(ch as Node3D).visible = on
	if star:
		star.visible = on


## The sun's rays (CosmosGodRays): where it is on screen; how strong - in a world's air by
## day, the sun ahead of you (on screen or near it), less under cloud, none under a storm;
## golden low.
func _god_rays(lp: CosmosPlanet, w: Dictionary, inside: bool) -> void:
	if _rays == null or star == null or cam == null:
		return
	var k := 0.0
	var e := 1.0
	var sp := star.global_position
	var to_sun := (sp - cam.global_position).normalized()
	var facing := to_sun.dot(-cam.global_basis.z)
	if lp and not inside and dungeon == null and facing > 0.05 and lp.atmo_radius > lp.radius:
		var local := cam.global_position - lp.global_position
		var near := 1.0 - smoothstep(0.3, 1.0, (local.length() - lp.radius) / (lp.atmo_radius - lp.radius))
		e = local.normalized().dot(to_sun)
		var uv := cam.unproject_position(sp) / get_viewport().get_visible_rect().size
		var on := 1.0 - smoothstep(0.25, 0.7, maxf(maxf(-uv.x, uv.x - 1.0), maxf(-uv.y, uv.y - 1.0)))   # (the sun on screen, or not far off it)
		k = 0.65 * near * smoothstep(-0.04, 0.1, e) * smoothstep(0.05, 0.45, facing) * on
		k *= 1.0 - 0.55 * float(w.get("cover", 0.0)) - 0.4 * float(w.get("storm", 0.0)) - 0.3 * float(w.get("precip", 0.0))
		_rays.sun_uv = uv
	_rays.strength = maxf(k, 0.0)
	_rays.tint = Color(1.0, 0.94, 0.82).lerp(Color(1.0, 0.6, 0.3), 1.0 - smoothstep(0.0, 0.35, e))


## The weather's veil: rain, snow, ash falling round you close the distance in - a grey
## wall of rain, a blizzard's whiteout, an ash storm's murk (the environment's fog).
func _weather_fog(w: Dictionary, indoors: bool) -> void:
	var p := 0.0 if indoors or weather_fx == null or weather_fx.sheltered else float(w.get("precip", 0.0))
	var falls := str(w.get("falls", "rain"))
	var storm := float(w.get("storm", 0.0))
	var dens := p * (0.004 + 0.012 * storm) * (2.2 if falls == "snow" else (1.6 if falls == "ash" else 1.0))
	var on := dens > 0.0004
	if _env.fog_enabled != on:
		_env.fog_enabled = on
	if not on:
		return
	var col := Color(0.62, 0.65, 0.7) if falls == "rain" else (Color(0.85, 0.88, 0.93) if falls == "snow" else Color(0.38, 0.35, 0.32))
	_env.fog_light_color = col * (0.35 + 0.65 * light.light_energy)
	_env.fog_density = dens
	_env.fog_sky_affect = 0.85
	_env.fog_sun_scatter = 0.0


## You on foot under the ground: down in what's carved (a cave, a tunnel, a pit) more
## than a couple of metres under the ground's face.
func _under_ground() -> bool:
	if walker == null or walker.deck != null or walker.planet == null:
		return false
	var local := walker.global_position - walker.planet.global_position
	var sh := walker.planet.shape
	return sh.carved_near(local) and sh.height(local.normalized()) - (local.length() - walker.planet.radius) > 2.0


## The built dungeons round you (their walls: the camera's, your bolts', the sights').
func dungeons_live() -> Array:
	var out: Array = []
	for key in _dungeon_live:
		var d = _dungeon_live[key]["node"]
		if is_instance_valid(d) and (d as CosmosDungeon).built:
			out.append(d)
	return out


## The floor in a built dungeon under planet-local `local` (m above the radius),
## or -INF if it's not in one - its own floors, walls and roof stand for the rock
## there (the walker's floor, the camera: none of the carved ground's sums).
func dungeon_floor(pl: CosmosPlanet, local: Vector3) -> float:
	for d: CosmosDungeon in dungeons_live():
		if d.planet == pl:
			var dl: Vector3 = d.to_local(pl.global_position + local)
			if d.inside(dl):
				return (d.to_global(Vector3(dl.x, d.floor_top(dl), dl.z)) - pl.global_position).length() - pl.radius
	return -INF


## The dungeon you're in (its rooms, its corridors, its doorway), or null.
func _dungeon_here() -> CosmosDungeon:
	if walker == null or walker.deck != null:
		return null
	for d: CosmosDungeon in dungeons_live():
		if d.planet == walker.planet and d.inside(d.to_local(walker.global_position)):
			return d
	return null


## A cave's or dungeon's chest, by its world and its seed (CosmosGame.extra "looted").
static func _chest_key(pl: CosmosPlanet, site: Dictionary) -> String:
	return "%s:%d" % [str(pl.rec.get("name", pl.name)), int(site.get("seed", 0))]


## The chest in its deepest room: drachmas, once.
func open_dungeon_chest() -> void:
	var d := dungeon_chest_here()
	if d == null:
		return
	d.chest_open = true
	_loot(d.planet, d.site)


## The dungeon whose shut chest is within reach of you, or null.
func dungeon_chest_here() -> CosmosDungeon:
	if walker == null or walker.deck != null:
		return null
	for d: CosmosDungeon in dungeons_live():
		var hl := d.to_local(walker.global_position)
		if not d.chest_open and absf(hl.y - d.chest_at.y) < 2.0 and Vector2(hl.x - d.chest_at.x, hl.z - d.chest_at.z).length() < 2.2:
			return d
	return null


## A chest's drachmas, once ever (its key in the save's "looted").
func _loot(pl: CosmosPlanet, site: Dictionary) -> void:
	var looted: Array = CosmosGame.extra.get("looted", [])
	looted.append(_chest_key(pl, site))
	CosmosGame.extra["looted"] = looted
	var dr := 800 + _life_rng.randi_range(0, 1200)
	if str(site.get("kind", "")) == "dungeon":
		dr *= 2
	CosmosGame.data.add_credits(dr)
	hud.flash("The chest: %d drachmas" % dr, 4.0)


# --- Talking: Kilon Alios ------------------------------------------------------------

## Kilon's conversation (QuestData.GIVER - the 2D game's: its lines, its voices):
## his greeting, then what you may ask him - who he is, who you are, where you
## are, your mission, what you may become - the main quest (offered, or how it
## goes), and farewell. The story's dialogue box (its portrait), a menu of the
## questions in the game's theme under it.
var _talk_layer: CanvasLayer
var _dialogue: Control
var _talk_menu: PanelContainer


func talk_kilon() -> void:
	_talk_ui()
	_dialogue.play(QuestData.GIVER.get("greeting", []), _talk_choices)


func _talk_ui() -> void:
	if _talk_layer == null:
		_talk_layer = CanvasLayer.new()
		_talk_layer.layer = 6
		_talk_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_talk_layer)
		_dialogue = preload("res://scripts/ui/dialogue.gd").new()
		_talk_layer.add_child(_dialogue)
		_talk_menu = PanelContainer.new()
		_talk_menu.add_theme_stylebox_override("panel", NeonTheme.box(NeonTheme.HEAD))   # (the game's theme)
		_talk_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_talk_menu.offset_left = -300
		_talk_menu.offset_right = 300
		_talk_menu.offset_top = -420
		_talk_menu.offset_bottom = -160
		_talk_layer.add_child(_talk_menu)
		_talk_menu.add_child(VBoxContainer.new())
	if walker:
		walker.control = false
		walker.drive = {}
	_talk_menu.hide()


## Talking to one of a port's people (CosmosHangar.people[i]): a greeting in
## the way of their work, then - who they are, the news, work (one of the
## station's missions: its pay, Accept / Not now), farewell.
var _talker := -1


func talk_port(i: int) -> void:
	if hangar == null or i < 0 or i >= hangar.people.size():
		return
	_talker = i
	hangar.face(i, hangar.to_local(walker.global_position) if walker else Vector3.ZERO, true)
	_talk_ui()
	var p: Dictionary = hangar.people[i]
	_dialogue.play([[_talker_name(), _port_line("hello", str(p["role"]))]], _port_choices)


func _talker_name() -> String:
	var p: Dictionary = hangar.people[_talker]
	return "%s, %s" % [p["name"], hangar.role_name(_talker).to_lower()]


const PORT_LINES := {
	"hello": {"dock": "Mind the lifts - they don't stop for anyone.", "carrier": "Coming through! These won't carry themselves.",
		"guard": "Keep your weapon stowed in the port, captain.", "visitor": "One moment - the prices here change by the minute.",
		"bartender": "What'll it be? First one's on the house if you bring news.", "patron": "Another captain! Sit, sit - the stars aren't going anywhere.",
		"officer": "Harbour office. Papers in order? Good.", "traveller": "Waiting for passage. Again."},
	"who": {"dock": "I work the deck - forty years of ships coming down those shafts.", "carrier": "Cargo hand. Whatever comes in, I carry.",
		"guard": "Port guard. Fire on a ship near %s and the station's guns will answer - the fines come first, but not for murder.",
		"visitor": "A merchant. I buy where it's cheap and sell where it isn't - the terminals tell me which.", "bartender": "I keep the bar. I hear everything that comes through this port.",
		"patron": "A spacer between ships. Ask me about the lanes - I've flown most of them.", "officer": "I assign the pads and the work - the station always needs captains.",
		"traveller": "Just passing through - a merchant without a ship until mine is repaired."},
}


func _port_line(kind: String, role: String) -> String:
	var st_name := label_of(port_station()) if port_station() else "the station"
	var t: String = PORT_LINES.get(kind, {}).get(role, "")
	return t % st_name if t.contains("%s") else t


func _port_choices() -> void:
	if hangar == null or _talker < 0:
		_talk_end()
		return
	var p: Dictionary = hangar.people[_talker]
	var role := str(p["role"])
	var box: VBoxContainer = _talk_menu.get_child(0)
	for c in box.get_children():
		c.queue_free()
	var add := func(text: String, then: Callable):
		var b := Button.new()
		b.text = text
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		b.pressed.connect(func():
			_talk_menu.hide()
			then.call())
		box.add_child(b)
	var who := _talker_name()
	var life: Array = People.story(str(p.get("pid", "")))
	if life.is_empty():
		add.call("Who are you?", func(): _dialogue.play([[who, _port_line("who", role)]], _port_choices))
	else:   # (their own life: their work, their ship and where it's bound, their family, their friends, lately)
		add.call("Who are you?", func(): _dialogue.play(life.map(func(l): return [who, l]), _port_choices))
	add.call("Any news?", func(): _dialogue.play([[who, _port_news()]], _port_choices))
	if role != "guard":
		add.call("Any work for me?", _port_work)
	for ch in sandbox.port_choices(role, who):   # (a package for this station; bounty vouchers)
		add.call(ch[0], ch[1])
	add.call("Farewell", func(): _dialogue.play([[who, "Fair winds, captain."]], _port_end))
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_talk_menu.show()
	(box.get_child(0) as Button).grab_focus.call_deferred()


## The latest of the sector's news (Galaxy.news), as they tell it.
func _port_news() -> String:
	var n: Array = Galaxy.news
	if n.is_empty():
		return "Quiet lanes lately. Too quiet, some say."
	var picks: Array = []
	for k in range(n.size() - 1, maxi(-1, n.size() - 3), -1):
		picks.append(str(n[k].get("text", "")))
	return "They say: " + " And: ".join(picks)


## One of the station's missions (its own pick of them), offered.
func _port_work() -> void:
	var who := _talker_name()
	var pst := port_station()
	if pst == null:
		_port_choices()
		return
	var list: Array = CosmosGame.missions.offers_for(str(pst.record.get("name", "")), str(pst.record.get("empire", "")))
	if list.is_empty():
		_dialogue.play([[who, "Nothing today. Ask again when the haulers come in."]], _port_choices)
		return
	var m: Dictionary = list[(_talker * 3 + hangar.people.size()) % list.size()]
	if not CosmosGame.missions.available(m):
		_dialogue.play([[who, "I'd have work, but not for someone the %s doesn't trust yet. %s" % [Galaxy.empire_name(str(m.get("empire", ""))), CosmosGame.missions.required_text(m)]]], _port_choices)
		return
	_dialogue.play([[who, "%s - %s Pays %s." % [m["title"], m.get("desc", ""), CosmosGame.missions.reward_text(m)]]], func():
		var box: VBoxContainer = _talk_menu.get_child(0)
		for c in box.get_children():
			c.queue_free()
		for pick in [["Accept", true], ["Not now", false]]:
			var b := Button.new()
			b.text = pick[0]
			b.process_mode = Node.PROCESS_MODE_ALWAYS
			var yes: bool = pick[1]
			b.pressed.connect(func():
				_talk_menu.hide()
				if yes and CosmosGame.missions.accept(m):
					hud.flash("Mission accepted: %s" % m["title"], 4.0)
					_dialogue.play([[who, "Good. Don't make me regret it."]], _port_choices)
				elif yes:
					_dialogue.play([[who, "You've too much on your plate already, captain."]], _port_choices)
				else:
					_dialogue.play([[who, "Suit yourself."]], _port_choices))
			box.add_child(b)
		get_tree().paused = true
		_talk_menu.show()
		(box.get_child(0) as Button).grab_focus.call_deferred())


## A station in trouble calling you (CosmosLaw): besieged or burning, it asks for
## help - its defence and repair jobs (Missions.crisis_offers), well paid.
var _hail_st: CosmosStation = null


func hail_station(st: CosmosStation, siege: bool) -> void:
	_hail_st = st
	_talk_ui()
	var who := "%s command" % label_of(st)
	var foes: Array = Fleets.besiegers(system_id).filter(func(e): return Galaxy.at_war(e, str(st.record.get("empire", ""))))
	var line := ("Any ship, any ship! %s is under attack by the %s. We need every gun we can get - the pay is good." % [label_of(st), Galaxy.empire_name(foes[0])]) if siege and not foes.is_empty() \
		else ("%s is burning - our crews need materials for the repairs. We'll pay well for them." % label_of(st))
	_dialogue.play([[who, line]], _hail_choices)


func _hail_choices() -> void:
	var st := _hail_st
	if st == null or not is_instance_valid(st):
		_talk_end()
		return
	var who := "%s command" % label_of(st)
	var rec_st: Dictionary = Galaxy.stations.get(str(st.record.get("id", "")), st.record)
	var jobs: Array = CosmosGame.missions.crisis_offers(rec_st, str(st.record.get("empire", ""))).filter(func(m): return not CosmosGame.missions.active.has(m))
	var box: VBoxContainer = _talk_menu.get_child(0)
	for c in box.get_children():
		c.queue_free()
	for m in jobs.slice(0, 3):
		var b := Button.new()
		b.text = "%s (%s)" % [m["title"], CosmosGame.missions.reward_text(m)]
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		var mm: Dictionary = m
		b.pressed.connect(func():
			_talk_menu.hide()
			if CosmosGame.missions.accept(mm):
				hud.flash("Mission accepted: %s" % mm["title"], 4.0)
				_dialogue.play([[who, "%s Thank you, captain." % mm.get("desc", "")]], _talk_end)
			else:
				_dialogue.play([[who, "You can't take that on now, captain."]], _hail_choices))
		box.add_child(b)
	var no := Button.new()
	no.text = "Not now"
	no.process_mode = Node.PROCESS_MODE_ALWAYS
	no.pressed.connect(func():
		_talk_menu.hide()
		_dialogue.play([[who, "Then fly safe - and stay clear of the fighting."]], _talk_end))
	box.add_child(no)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_talk_menu.show()
	(box.get_child(0) as Button).grab_focus.call_deferred()


## Talking to one of the sector's people out in the world (a town's resident):
## who they are - their life - the news, farewell.
var _person_id := ""


func talk_person(pid: String) -> void:
	var p := People.person(pid)
	if p.is_empty():
		return
	_person_id = pid
	_talk_ui()
	_dialogue.play([[_person_title(), "Well met, stranger."]], _person_choices)


func _person_title() -> String:
	var p := People.person(_person_id)
	return "%s, %s" % [People.full_name(p), People.job_name(p)]


func _person_choices() -> void:
	var box: VBoxContainer = _talk_menu.get_child(0)
	for c in box.get_children():
		c.queue_free()
	var who := _person_title()
	for pick in [["Who are you?", func(): _dialogue.play(People.story(_person_id).map(func(l): return [who, l]), _person_choices)],
			["Any news?", func(): _dialogue.play([[who, _port_news()]], _person_choices)],
			["Farewell", func(): _dialogue.play([[who, "Go well."]], _talk_end)]]:
		var b := Button.new()
		b.text = pick[0]
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		var then: Callable = pick[1]
		b.pressed.connect(func():
			_talk_menu.hide()
			then.call())
		box.add_child(b)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_talk_menu.show()
	(box.get_child(0) as Button).grab_focus.call_deferred()


func _port_end() -> void:
	if hangar and _talker >= 0 and _talker < hangar.people.size():
		hangar.face(_talker, Vector3.ZERO, false)
	_talker = -1
	_talk_end()


func _talk_choices() -> void:
	var G: Dictionary = QuestData.GIVER
	var q: CosmosQuest = CosmosGame.quest
	var box: VBoxContainer = _talk_menu.get_child(0)
	for c in box.get_children():
		c.queue_free()
	var add := func(text: String, then: Callable):
		var b := Button.new()
		b.text = text
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		b.pressed.connect(func():
			_talk_menu.hide()
			then.call())
		box.add_child(b)
	for t in G.get("topics", []):
		var lines: Array = t["lines"]
		add.call(str(t["ask"]), func(): _dialogue.play(lines, _talk_choices))
	if q and q.stage < 0 and not q.finished:
		add.call(str(G.get("quest_ask", "The quest")), func(): _dialogue.play(G.get("offer", []), _quest_choice))
	elif q and not q.finished:
		add.call(str(G.get("quest_ask_later", "The thread")), func():
			_dialogue.play(G.get("later", []) + [[QuestData.KILON, q.objective_text()]], _talk_choices))
	elif q:
		add.call(str(G.get("quest_ask_later", "The thread")), func(): _dialogue.play(G.get("done", []), _talk_choices))
	add.call("Farewell", func(): _dialogue.play(G.get("farewell", []), _talk_end))
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_talk_menu.show()
	(box.get_child(0) as Button).grab_focus.call_deferred()


func _quest_choice() -> void:
	var G: Dictionary = QuestData.GIVER
	var box: VBoxContainer = _talk_menu.get_child(0)
	for c in box.get_children():
		c.queue_free()
	for pick in [["Accept", true], ["Not now", false]]:
		var b := Button.new()
		b.text = pick[0]
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		var yes: bool = pick[1]
		b.pressed.connect(func():
			_talk_menu.hide()
			if yes:
				CosmosGame.quest.stage = 0
				hud.flash("Main quest: %s" % str(G.get("quest_title", "")), 4.0)
				var first: Array = CosmosGame.quest.current().get("dialogue", [])
				_dialogue.play(G.get("accepted", []) + first, _talk_choices)
			else:
				_dialogue.play(G.get("declined", []), _talk_choices))
		box.add_child(b)
	get_tree().paused = true
	_talk_menu.show()


## A conversation: `lines` ([[who, text]...]) said, then `choices` ([[text, Callable]...])
## offered - each one closes the menu and runs (talking on, or ending it); none: it ends.
func converse(lines: Array, choices: Array) -> void:
	_talk_ui()
	_dialogue.play(lines, func(): _offer(choices))


func _offer(choices: Array) -> void:
	if choices.is_empty():
		_talk_end()
		return
	var box: VBoxContainer = _talk_menu.get_child(0)
	for c in box.get_children():
		c.queue_free()
	for ch in choices:
		var b := Button.new()
		b.text = str(ch[0])
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		var then: Callable = ch[1]
		b.pressed.connect(func():
			_talk_menu.hide()
			then.call())
		box.add_child(b)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_talk_menu.show()
	(box.get_child(0) as Button).grab_focus.call_deferred()


## What a left click on foot does here, if anything: [text, action] - the grab hand at
## the crosshair (CosmosHud) - or [] (the click fires).
func interaction() -> Array:
	if walker == null:
		return []
	var t := terminal_here()
	if not t.is_empty():
		return t
	if walker.deck == ship.interior and ship.interior.at_seat(ship.interior.to_local(walker.global_position)):
		return ["Take the controls", "board"]
	return []


## The left click on foot: does what's in reach (true), or nothing (false: it fires).
func interact() -> bool:
	var t := interaction()
	if t.is_empty():
		return false
	if t[1] == "board":
		board()
	else:
		use_terminal(t)
	return true


## Something you did, for the tutorial to note (CosmosTutor).
func note_event(e: String) -> void:
	if tutor:
		tutor.on_event(e)


func _talk_end() -> void:
	_talk_menu.hide()
	get_tree().paused = false
	if walker:
		walker.control = true


# --- Space monsters --------------------------------------------------------------------

## The lairs near you: their creatures out (and back in when you're far).
func _lairs_tick() -> void:
	monsters = monsters.filter(func(x): return is_instance_valid(x) and not x.dead)
	if docked:
		return
	var f := focus().global_position
	for lr: CosmosLair in lairs:
		if not is_instance_valid(lr):
			continue
		var d := lr.global_position.distance_to(f)
		if d < LAIR_NEAR and not is_instance_valid(lr.monster):
			var m := CosmosMonster.new()
			m.setup(lr.kind(), self, int(lr.sig.get("seed", 1)), lr.sig)
			world.add_child(m)
			m.global_position = lr.global_position
			m.lair = lr.global_position
			lr.monster = m
			monsters.append(m)
		elif d > LAIR_NEAR * 2.2 and is_instance_valid(lr.monster) and lr.monster.global_position.distance_to(f) > LAIR_NEAR * 2.0:
			monsters.erase(lr.monster)
			lr.monster.queue_free()
			lr.monster = null


func monster_died(m: CosmosMonster) -> void:
	monsters.erase(m)
	if target == m:
		target = null
	var bounty := int(4000.0 * m.mult)
	CosmosGame.data.add_credits(bounty)
	m.signal_rec["done"] = true
	for lr: CosmosLair in lairs.duplicate():
		if lr.monster == m:
			lairs.erase(lr)
			lr.queue_free()
	hud.flash("%s slain - %d dr from the bio-signature's bounty" % [m.label, bounty], 4.0)


# --- Towns -------------------------------------------------------------------------

## The towns of the planet you're near: built as you come within TOWN_NEAR
## (on a worker - CosmosTown.poll brings them in), freed as you leave; their
## people out in the streets when you're close.
func _towns_tick() -> void:
	var f := focus().global_position
	for pl: CosmosPlanet in planets:
		if pl.towns.is_empty():
			continue
		var near := pl.global_position.distance_to(f) < pl.radius + TOWN_NEAR * 2.0
		if not _towns.has(pl):
			if not near:
				continue
			var list: Array = []
			list.resize(pl.towns.size())
			_towns[pl] = list
		var list: Array = _towns[pl]
		for i in pl.towns.size():
			var s: Dictionary = pl.towns[i]
			if near and list[i] == null:   # (its marker: a node while you're near its planet)
				var xf := CosmosTown.frame(s, pl.radius)
				var t := CosmosTown.new()
				t.setup(pl, s)
				pl.add_child(t)   # (on its world: it goes round the star with it, nothing to carry)
				t.global_transform = Transform3D(xf.basis, pl.global_position + xf.origin)
				list[i] = t
			elif not near and list[i] != null:
				(list[i] as Node).queue_free()
				list[i] = null
			if list[i] == null:
				continue
			var town: CosmosTown = list[i]
			var d := town.global_position.distance_to(f)
			if d < TOWN_NEAR:
				town.want(true)
			elif d > TOWN_NEAR * 1.4:
				town.want(false)
			if town.built:
				_town_people(town, d)
		if not near:
			_towns.erase(pl)
	for x in citizens:
		if is_instance_valid(x) and not is_instance_valid(x.town):
			x.queue_free()   # (its town gone)
	citizens = citizens.filter(func(x): return is_instance_valid(x) and is_instance_valid(x.town))


## A town's people: out about its streets within 400 m (one more a tick), gone past 600.
func _town_people(t: CosmosTown, d: float) -> void:
	citizens = citizens.filter(func(x): return is_instance_valid(x) and not x.is_queued_for_deletion())
	var mine := citizens.filter(func(x): return x.town == t)
	if d > 600.0:
		for x in mine:
			x.queue_free()
		return
	if str(t.site["kind"]) == "city" and d < 400.0 and t.built and not CosmosSandbox.ROLES.keys().all(func(r): return mine.any(func(x): return x.role == r)):
		for sp in CosmosSandbox.spots():   # (the city's ore buyer, courier's office and local pilot, by its landing field - each one missing)
			if mine.any(func(x): return x.role == sp[0]) or (sp[0] == "pilot" and sandbox and sandbox.pilot_busy(t)):
				continue   # (there - or the pilot gone aboard his hired ship, still on the field)
			var k := CosmosNpc.new()
			k.cosmos = self
			k.citizen_of(t, hash(str(t.site["name"]) + str(sp[0])), str(sp[0]))
			world.add_child(k)
			k.global_position = t.to_global(t.port + (sp[1] as Vector3))
			citizens.append(k)
			mine.append(k)
	mine = mine.filter(func(x): return not x.role in CosmosSandbox.ROLES)
	var want := 9 if str(t.site["kind"]) == "city" else 5
	if d < 400.0 and mine.size() < want and not t.spots.is_empty():
		# (one of its own people - the town's residents (People): out in its streets, their face their own)
		var key := "%s:%s" % [str(t.planet.rec.get("id", "")), str(t.site.get("name", ""))]
		var folk: Array = People.town_folk(key, str(t.site.get("empire", "")), str(t.site["kind"]) == "city") if People.populated else []
		var out: Array = mine.map(func(x): return x.pid)
		folk = folk.filter(func(i): return not i in out)
		var pid: String = folk[_life_rng.randi() % folk.size()] if not folk.is_empty() else ""
		var npc := CosmosNpc.new()
		npc.cosmos = self
		npc.citizen_of(t, hash(pid) if pid != "" else _life_rng.randi())
		if pid != "":
			npc.pid = pid
			npc.label = "%s, %s" % [People.full_name(People.person(pid)), People.job_name(People.person(pid))]
		world.add_child(npc)
		var at: Vector3 = t.spots[_life_rng.randi() % t.spots.size()]
		npc.global_position = t.to_global(at)
		citizens.append(npc)


## Indoors in a town (under a roof): a warm light over you - the rooms are
## shut from the sun (one light, no shadows: cheap).
var _lamp: OmniLight3D


func _indoor_light() -> void:
	var inside := dungeon != null and is_instance_valid(walker)   # (the lamp over you on foot - aboard, none)
	if not inside and walker and walker.deck == null and walker.planet:
		var t := town_at(walker.planet, walker.global_position)
		inside = t != null and t.indoors(t.to_local(walker.global_position))
		if not inside and builds:
			inside = builds.indoors(walker.global_position)
	if inside and _lamp == null:
		_lamp = OmniLight3D.new()
		_lamp.light_color = Color(1.0, 0.82, 0.6)
		_lamp.light_energy = 1.6
		_lamp.omni_range = 11.0
		_lamp.omni_attenuation = 0.8
		_lamp.shadow_enabled = false
		world.add_child(_lamp)
	if _lamp:
		_lamp.visible = inside
		if inside:
			_lamp.global_position = walker.global_position + walker.up() * 2.3


## The towns' floors under planet-local `local` (steps, roofs: what's not
## above its feet + a step): metres above the radius, or -INF.
func town_floor(pl: CosmosPlanet, local: Vector3) -> float:
	var best := -INF
	for t in _towns.get(pl, []):
		if t == null or not t.built:
			continue
		var tl: Vector3 = t.to_local(pl.global_position + local)
		var r: float = t.site["r"]
		if absf(tl.x) > r or absf(tl.z) > r or tl.y > 40.0 or tl.y < -3.0:
			continue
		var top: float = t.floor_top(tl)
		if top > 0.01:
			best = maxf(best, (t.to_global(Vector3(tl.x, top, tl.z)) - pl.global_position).length() - pl.radius)
	if builds:   # (and what you've built)
		best = maxf(best, builds.floor_at(pl, local))
	for d: CosmosDungeon in dungeons_live():   # (a dungeon's floors: its dais, its steps)
		if d.planet == pl:
			var dl: Vector3 = d.to_local(pl.global_position + local)
			if d.inside(dl):
				var top: float = d.floor_top(dl)
				if top > -49.0:
					best = maxf(best, (d.to_global(Vector3(dl.x, top, dl.z)) - pl.global_position).length() - pl.radius)
	return best


## The town that `p` (global) is in, or null.
func town_at(pl: CosmosPlanet, p: Vector3) -> CosmosTown:
	for t in _towns.get(pl, []):
		if t != null and t.built:
			var tl: Vector3 = t.to_local(p)
			var r: float = t.site["r"]
			if absf(tl.x) < r and absf(tl.z) < r and tl.y < 40.0:
				return t
	return null


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
		if pl.shape.sea > 0 and h < 2.0 or pl.shape.cleared(d):
			continue   # (not in the sea, not in a town)
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
	_dungeon_mouths(pl, here)
	_cave_life(pl, here)
	_dungeon_life(pl, here)
	dungeon = _dungeon_here()
	if dungeon:
		_surface_shown(false)   # (the ground's patches made since: not drawn either)
		return   # (below: the surface's life waits)
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
	pl.add_child(n)   # (on its world: moves with it)
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
	for d: CosmosDungeon in dungeons_live():
		bt = minf(bt, d.cam_hit(o, dir, bt))   # (a dungeon's walls)
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
			if pl.shape.carved_near(local):   # (dug ground - a cave, a tunnel, a dungeon: its rock, not the face above)
				if pl.shape.density(local) < 0.0:
					bt = t
					break
				t += 0.5
				continue
			if local.length() < pl.radius + pl.shape.surface(local.normalized()):
				bt = t
				break
			t += 2.0 + t * 0.03
	if walker and walker.deck == null:   # (never between the camera and you: the rifle doesn't turn round to fire behind you)
		var past := (walker.global_position - o).dot(dir) + 1.5
		if bt < past:
			bt = past
			best = null
	return [best, o + dir * bt, bt]


## The walker's rifle: a bolt from the muzzle at what the sights are on.
func walker_fire(w: CosmosWalker) -> void:
	var a := aim()
	var muzzle := w.muzzle()   # (the rifle's own muzzle, raised and aimed at where this goes)
	CosmosBolt.fire(self, muzzle, (a[1] as Vector3) - muzzle, "player", CosmosWalker.BOLT_DAMAGE)


func creature_died(c: CosmosCreature) -> void:
	CosmosLoot.of(self).drop_for(c)   # (what it leaves: a pouch by the body)
	kills += 1
	if hud:
		hud.flash("%s down" % c.kind["name"], 2.0)


func npc_died(n: CosmosNpc) -> void:
	CosmosLoot.of(self).drop_for(n)
	kills += 1
	if hud:
		hud.flash("%s down" % (n.label if n.label != "" else "Pirate"), 2.0)


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
		var bed = CosmosBuilds.bed_on(pl)
		if bed != null:   # (your bed on this world: you wake in it)
			var bl: Vector3 = bed
			walker.revive(pl.global_position + bl.normalized() * (pl.radius + walker.floor_at(bl) + 0.05))
			_shift_origin(true)
			return
		if ship_elsewhere:   # (no ship of yours here: back on your feet by the nearest town's field)
			var best := walker.global_position - pl.global_position
			var bd := INF
			for s in pl.towns:
				var f := CosmosSandbox.field_of(pl, s)
				var d := f.origin.distance_to(walker.global_position - pl.global_position)
				if d < bd:
					bd = d
					best = f * Vector3(-24.0, 0.0, 4.0)
			walker.revive(pl.global_position + best.normalized() * (pl.radius + walker.floor_at(best) + 0.05))
			_shift_origin(true)
			return
		var at := ship.interior.to_global(ship.interior.ramp_foot() + Vector3(0, 0, 3.0))   # (by the foot of your ship's ramp)
		var local := at - pl.global_position
		walker.revive(pl.global_position + local.normalized() * (pl.radius + walker.floor_at(local) + 0.05))
		_shift_origin(true))


# --- Docking (stage 4) ------------------------------------------------------------

func station_near_to(p: Vector3, within: float) -> CosmosStation:
	for st: CosmosStation in stations:
		if st.global_position.distance_to(p) < within:
			return st
	return null


## The station near enough to dock at, or null.
func station_near() -> CosmosStation:
	for st: CosmosStation in stations:
		if st.global_position.distance_to(ship.global_position) - st.reach < DOCK_REACH:
			return st
	return null


## L near a station: ask it for a pad (L again: cancel). It lights up; you fly to
## it and set down on it yourself - the thrusters (R / F, Q / E) for
## the last metres - slower than PAD_SPEED, level with it: its lift takes the
## ship down into the hangar. `auto` (tests, tours): the docking computer
## flies it there.
func request_dock(auto := false) -> bool:
	if not dock_pad.is_empty() and not docked and _dock.is_empty() and not auto:
		_release_pad()
		hud.flash("Docking request cancelled")
		return false
	var st := station_near()
	if st == null or ship.state != "fly" or docked:
		if hud:
			hud.flash("No station near enough to dock (within %s)" % CosmosHud._dist(DOCK_REACH))
		return false
	var no := law.refuses(st) if law and not auto else ""
	if no != "":
		hud.flash(no, 4.0)
		return false
	var pad := st.free_pad(CosmosShip.HULL_R * 2.6, ship.global_position)
	if pad.is_empty():
		hud.flash("%s: no pad free - wait for one" % label_of(st))
		return false
	_release_pad()
	pad["owner"] = ship
	st.light_pad(pad, true)
	dock_station = st
	dock_pad = pad
	_open_port(st, pad)   # (built as you come in: on a worker, its people a frame each)
	if auto:
		var xf := st.pad_transform(pad)
		ship.state = "docking"
		ship.velocity = Vector3.ZERO
		ship.cruise = 0
		var inv := st.global_transform.affine_inverse()   # (its path the station's: the floating origin moves under it)
		_dock = {"phase": 0, "t": 0.0, "from": inv * ship.global_transform,
			"to": inv * Transform3D(_level(pad_nose(xf), xf.basis.y), xf.origin + xf.basis.y * (CosmosShip.GEAR + 4.0))}
	hud.flash("%s: pad %d is yours - set down on it" % [label_of(st), int(pad["id"])], 4.0)
	return true


## A basis facing `f` (flattened) with `u` up.
static func _level(f: Vector3, u: Vector3) -> Basis:
	var g := f - u * f.dot(u)
	if g.length() < 0.01:
		g = u.cross(Vector3.RIGHT if absf(u.x) < 0.9 else Vector3.FORWARD)
	return Basis.looking_at(g.normalized(), u)


## On the lift, settling onto the pad, lifting off it.
func is_docking() -> bool:
	return not _dock.is_empty()


func _release_pad() -> void:
	if not dock_pad.is_empty():
		if dock_pad.get("owner") == ship:
			dock_pad["owner"] = null
		if is_instance_valid(dock_station):
			dock_station.light_pad(dock_pad, false)
	dock_pad = {}
	if not docked:
		_close_port()


## Set down on your pad: inside its square, low, slow and level - touchdown.
func _pad_watch() -> void:
	if dock_pad.is_empty() or docked or not _dock.is_empty() or ship.state != "fly":
		return
	var st := dock_station
	if not is_instance_valid(st) or ship.global_position.distance_to(st.global_position) > st.reach + DOCK_REACH * 2.0:
		_release_pad()
		hud.flash("Docking cancelled - too far from the station")
		return
	var xf := st.pad_transform(dock_pad)
	var l := xf.affine_inverse() * ship.global_position
	var half := float(dock_pad["size"]) * 0.5
	if absf(l.x) > half or absf(l.z) > half or l.y < -1.0 or l.y > CosmosShip.GEAR + 6.0:
		return
	if ship.velocity.length() > PAD_SPEED or ship.global_basis.y.dot(xf.basis.y) < 0.85:
		return
	if pad_heading_off(xf, -ship.global_basis.z) > PAD_ALIGN:
		return   # (square on the pad: the nose to its top)
	ship.land_at(Transform3D(_level(pad_nose(xf), xf.basis.y), xf * Vector3(l.x, CosmosShip.GEAR, l.z)))
	_dock = {"phase": 1, "t": 0.0}
	hud.flash("Touchdown on pad %d" % int(dock_pad["id"]))


func _docking(delta: float) -> void:
	_pad_watch()
	if _dock.is_empty():
		return
	_dock["t"] += delta
	var t: float = _dock["t"]
	var st := dock_station
	match int(_dock["phase"]):
		0:   # (the docking computer: over the pad)
			var k := smoothstep(0.0, 1.0, minf(t / 5.0, 1.0))
			ship.global_transform = st.global_transform * (_dock["from"] as Transform3D).interpolate_with(_dock["to"], k)
			if t >= 5.0:
				ship.state = "fly"
				ship.velocity = Vector3.ZERO
				ship.throttle = 0.0
				_dock = {}
				_pad_watch()
		1:   # (settling onto the pad)
			if ship.state == "landed":
				_dock = {"phase": 2, "t": 0.0, "at": st.to_local(ship.global_position)}
		2:   # (the lift: down its shaft into the port's hall, the shutters sliding shut over you)
			if hangar == null or hangar.station != st:
				_open_port(st, dock_pad)
			var k := minf(t / LIFT_TIME, 1.0)
			var depth := LIFT_DEPTH * smoothstep(0.0, 1.0, k)
			st.lower_pad(dock_pad, depth)
			ship.global_position = st.to_global(_dock["at"]) - st.global_basis.y * depth
			if depth > 30.0 and not _dock.has("shut"):
				_dock["shut"] = t   # (the ship below the platform's deck: the shutters close over it)
			var h := clampf((t - float(_dock.get("shut", t))) / HATCH_TIME, 0.0, 1.0)
			st.set_hatch(dock_pad, h)
			if k >= 1.0 and h >= 1.0:
				_enter_hangar(st)
				_dock = {}
		4:   # (undocking: the shutters slide open over you, then up the lift)
			_leave_hangar()
			_dock = {"phase": 5, "t": 0.0}
		5:
			st.set_hatch(dock_pad, 1.0 - clampf(t / HATCH_TIME, 0.0, 1.0))
			var t0 := HATCH_TIME * 0.9
			var k := clampf((t - t0) / LIFT_TIME, 0.0, 1.0)
			var depth := LIFT_DEPTH * (1.0 - smoothstep(0.0, 1.0, k))
			var xf := st.pad_transform(dock_pad)
			st.lower_pad(dock_pad, depth)
			ship.global_position = xf.origin + xf.basis.y * (CosmosShip.GEAR - depth)
			if k >= 1.0:
				st.set_hatch(dock_pad, 0.0)
				ship.take_off()
				_dock = {"phase": 6, "t": 0.0}
		6:   # (lifting off: the pad free again once you're clear of it)
			if ship.state == "fly" and (t > 6.0 or ship.global_position.distance_to(st.pad_transform(dock_pad).origin) > 150.0):
				_release_pad()
				_dock = {}


## The port under the pad's platform (CosmosHangar: its hall, its rooms, its
## people) - built as you're given the pad (on a worker; its people come in a
## frame at a time), freed when you've flown off.
func _open_port(st: CosmosStation, pad: Dictionary) -> void:
	var i := int(pad.get("platform", 0))
	if hangar and is_instance_valid(hangar) and hangar.station == st and hangar.platform == i:
		return
	_close_port()
	hangar = CosmosHangar.new()
	hangar.setup(st, i)
	st.add_child(hangar)


func _close_port() -> void:
	if hangar and is_instance_valid(hangar):
		hangar.queue_free()
	hangar = null


## Down the lift, in the port's hall: docked. (Its lift stays down, its
## shutters shut, while you're in.) Without a pad (a test, a tour): onto one.
func _enter_hangar(st: CosmosStation) -> void:
	dock_station = st
	if dock_pad.is_empty() or not st.pads.has(dock_pad):
		dock_pad = st.free_pad(CosmosShip.HULL_R * 2.6, ship.global_position)
		if dock_pad.is_empty():
			dock_pad = st.pads[0]
		dock_pad["owner"] = ship
	_open_port(st, dock_pad)
	var xf := st.pad_transform(dock_pad)
	st.lower_pad(dock_pad, LIFT_DEPTH)
	st.set_hatch(dock_pad, 1.0)
	var l := xf.affine_inverse() * ship.global_position
	if absf(l.x) > float(dock_pad["size"]) * 0.5 or absf(l.z) > float(dock_pad["size"]) * 0.5 or absf(l.y + LIFT_DEPTH - CosmosShip.GEAR) > 3.0:
		ship.global_transform = Transform3D(_level(pad_nose(xf), xf.basis.y), xf.origin + xf.basis.y * (CosmosShip.GEAR - LIFT_DEPTH))
	ship.state = "landed"
	ship.set_legs(true)
	ship.interior.ramp_end_y = -CosmosShip.GEAR
	ship.velocity = Vector3.ZERO
	ship.shield = ship.max_shield
	docked = true
	_shift_origin(true)
	if walker == null:
		note_event("docked")   # (you, at the controls - not your ship brought down the lift)
	Galaxy.visit_station(str(st.record.get("id", "")))
	CosmosGame.missions.on_docked(str(st.record.get("name", "")))
	hud.flash("Docked at %s - %s: get up, L / Space: undock" % [label_of(st), Keybinds.keys_text("stand_up")], 4.0)
	if not dry_run:
		CosmosGame.save(self)


## L / Space in the hangar: up the lift to the pad, and off.
func undock() -> void:
	if not docked or walker or not _dock.is_empty():
		return
	_dock = {"phase": 4, "t": 0.0}


func _leave_hangar() -> void:
	var st := dock_station
	docked = false
	note_event("undocked")
	if dock_pad.is_empty() or (dock_pad.get("owner") != null and dock_pad.get("owner") != ship and is_instance_valid(dock_pad.get("owner"))):
		dock_pad = st.free_pad(CosmosShip.HULL_R * 2.6, ship.global_position)
		if dock_pad.is_empty():
			dock_pad = st.pads[0]
	dock_pad["owner"] = ship
	var xf := st.pad_transform(dock_pad)
	var b := _level(pad_nose(xf), xf.basis.y)
	st.lower_pad(dock_pad, LIFT_DEPTH)
	st.set_hatch(dock_pad, 1.0)   # (shut over you, down the shaft)
	var l := xf.affine_inverse() * ship.global_position
	if absf(l.x) > float(dock_pad["size"]) * 0.5 or absf(l.z) > float(dock_pad["size"]) * 0.5:
		ship.global_transform = Transform3D(b, xf.origin + xf.basis.y * (CosmosShip.GEAR - LIFT_DEPTH))
	else:   # (the ship where it set down on the lift)
		b = ship.global_basis
		ship.global_position = xf.origin + xf.basis.y * (CosmosShip.GEAR - LIFT_DEPTH) + xf.basis * Vector3(l.x, 0, l.z)
	ship._land_to = Transform3D(b, ship.global_position + xf.basis.y * LIFT_DEPTH)
	ship.state = "landed"
	ship.set_legs(true)
	ship.velocity = Vector3.ZERO
	_shift_origin(true)
	cam.to_ship()
	cam.follow(1.0)
	hud.flash("Undocking from %s - pad %d" % [label_of(st), int(dock_pad["id"])])


## E in the hangar by a terminal: the station's service (Stage 5: the menus).
func terminal_here() -> Array:
	if walker == null:
		return []
	if walker.deck == ship.interior:
		var t := ship.interior.terminal_near(ship.interior.to_local(walker.global_position))
		if t.is_empty():
			return []
		return [t[0], ("device:%s" % t[1]) if t[1] is String else ("computer:%d" % int(t[1]))]
	if dungeon_chest_here() != null:
		return ["Open the chest", "chest"]
	if walker.deck is CosmosNpcInterior:   # (aboard a trader: the passenger seat beside its pilot's - and nothing outside its hull: not the townsfolk on the field under it)
		var inn := walker.deck as CosmosNpcInterior
		if not walker.seat.is_empty():
			return ["Get up from the seat", "npc_stand"]
		if inn.ok and inn.seat_pos != Vector3.INF and inn.seat.get("who") == null:
			var l := inn.to_local(walker.global_position)
			if Vector2(l.x - inn.seat_pos.x, l.z - inn.seat_pos.z).length() < 1.4:
				return ["Sit in the passenger seat", "npc_sit"]
		return []
	if not cave_chest_here().is_empty():
		return ["Open the chest", "cave_chest"]
	var lp := CosmosLoot.prompt(self)   # (the loot of the dead in reach)
	if not lp.is_empty():
		return lp
	if sandbox.box_near():
		return ["Pick up the package", "pkg_pick"]
	if builds and walker.deck == null:   # (a door, a gate, a chest, a bed of what you've built)
		var bp := builds.prompt(walker)
		if not bp.is_empty():
			return bp
	for x in citizens:   # (the city's ore buyer, courier's office, local pilot)
		if is_instance_valid(x) and x.role in CosmosSandbox.ROLES and x.global_position.distance_to(walker.global_position) < 3.5:
			return sandbox.prompt_for(x)
	for x in citizens:   # (a town's resident: their own life)
		if is_instance_valid(x) and x.pid != "" and not x.dead and x.global_position.distance_to(walker.global_position) < 3.0:
			return ["Talk to %s" % People.person(x.pid).get("n", "them"), "talk:person:" + x.pid]
	if hangar == null or walker.deck != hangar:
		return []
	if not walker.seat.is_empty():
		return ["Stand up", "stand"]
	var hl := hangar.to_local(walker.global_position)
	var sn := hangar.seat_near(hl, 0.8)
	if sn >= 0:
		return ["Sit down", "sit:%d" % sn]
	var t := hangar.terminal_near(hl)
	if not t.is_empty():
		return t
	var who := hangar.person_near(hl, 3.8)   # (across a counter, a desk)
	if who >= 0:
		return ["Talk to the %s" % hangar.role_name(who).to_lower(), "talk:port:%d" % who]
	sn = hangar.seat_near(hl, 1.4)
	if sn >= 0:
		return ["Sit down", "sit:%d" % sn]
	return []


func use_terminal(t: Array) -> void:
	var id := str(t[1])
	if id.begins_with("computer:"):
		open_computer(int(id.trim_prefix("computer:")))
	elif id.begins_with("device:"):
		open_device(id.trim_prefix("device:"))
	elif id.begins_with("svc:"):
		var x := instance_from_id(int(id.trim_prefix("svc:")))
		if is_instance_valid(x):
			sandbox.talk(x)
	elif id == "pkg_pick":
		sandbox.drop_or_pick()
	elif id == "loot":
		CosmosLoot.of(self).take()
	elif id.begins_with("sit:") and hangar and walker:
		var st: Dictionary = hangar.seats[int(id.trim_prefix("sit:"))]
		walker.sit(st, hangar.sit_point(st))
	elif id == "stand" and walker:
		walker.stand_up()
	elif id == "npc_sit" and walker and walker.deck is CosmosNpcInterior:
		var inn := walker.deck as CosmosNpcInterior
		walker.sit(inn.seat, inn.seat_pos)
		passenger_view(true)
	elif id == "npc_stand" and walker:
		walker.stand_up()
		passenger_view(false)
	elif id.begins_with("talk:person:"):
		talk_person(id.trim_prefix("talk:person:"))
	elif id.begins_with("talk:port:"):
		talk_port(int(id.trim_prefix("talk:port:")))
	elif id == "chest":
		open_dungeon_chest()
	elif id == "cave_chest":
		open_cave_chest()
	elif id.begins_with("build:"):
		builds.use(id)
	elif str(t[1]) == "8" and not sandbox.port_choices("officer", "The harbour office").is_empty():
		# (the harbour office's terminal: a package for this station, bounty vouchers - then its missions board)
		var ch: Array = sandbox.port_choices("officer", "The harbour office")
		ch.append(["The missions board", func():
			_talk_end()
			open_service(8)])
		converse([["The harbour office", "Harbour office - deliveries, bounties, the station's work."]], ch)
	else:
		open_service(t[1])


## The ship's computer (the Automaton: inventory, maps, archive) at page `tab` - on your ship's terminals.
var _computer: Control
var _proxy: CosmosShipProxy


## The menus' own layer: over both HUDs (never under the gauge, the toolbar,
## the log), under the Esc menu.
var _menu_layer: CanvasLayer


func _menus() -> CanvasLayer:
	if _menu_layer == null:
		_menu_layer = CanvasLayer.new()
		_menu_layer.name = "Menus"
		_menu_layer.layer = 5   # (over the FPS counter's 4, under the talk's 6 and the Esc menu's 50)
		add_child(_menu_layer)
	return _menu_layer


## While a menu is open the HUDs step aside (nothing of them over or round it).
func _huds_for_menus() -> void:
	var open := (_computer != null and _computer.visible) or (_station_menu != null and _station_menu.visible) or (_device_menu != null and _device_menu.visible) \
		or (_build_menu != null and _build_menu.visible) or (_chest_menu != null and _chest_menu.visible)
	if hud2d:
		hud2d.visible = not open
	if hud:
		hud.visible = not open


func open_computer(tab: int) -> void:
	_make_computer()
	if walker:
		walker.control = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_computer.open(tab)
	_huds_for_menus()


## The Automaton's screen made (hidden) - in a browser under the loading screen (its first
## opening there was a ~0.4 s frame), else the first time it's opened.
func _make_computer() -> void:
	if _computer == null:
		_computer = load("res://scenes/ui/ship_menu.tscn").instantiate()
		_computer.data = CosmosGame.data
		_computer.ship = _proxy
		_computer.world = self
		_menus().add_child(_computer)
		_computer.visibility_changed.connect(func():
			_huds_for_menus()
			if not _computer.visible:
				if walker:
					walker.control = true
				if _may_capture():
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
		_computer.visible = false


## One of your ship's devices (its refinery, its fabricator): its own window (DeviceMenu).
var _device_menu: Control

func open_device(kind: String) -> void:
	if _device_menu == null:
		_device_menu = DeviceMenu.new()
		_device_menu.data = CosmosGame.data
		_menus().add_child(_device_menu)
		_device_menu.visibility_changed.connect(func():
			_huds_for_menus()
			if not _device_menu.visible:
				if walker:
					walker.control = true
				if _may_capture():
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	if walker:
		walker.control = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_device_menu.open(kind)
	_huds_for_menus()


## The builder's menu (N with the builder in hand): its pieces, tier, style, paint, mode.
var _build_menu: BuildMenu
var _chest_menu: ChestMenu


func open_build_menu() -> void:
	if _build_menu == null:
		_build_menu = BuildMenu.new()
		_build_menu.builds = builds
		_menus().add_child(_build_menu)
		_build_menu.visibility_changed.connect(_menu_closed.bind(_build_menu))
	if _build_menu.visible:
		_build_menu.close()
		return
	if walker:
		walker.control = false
		walker.trigger = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_menu.open()
	_huds_for_menus()


## A chest you built: what's in it and what you have, to move between them.
func open_chest(pc: Dictionary) -> void:
	if _chest_menu == null:
		_chest_menu = ChestMenu.new()
		_menus().add_child(_chest_menu)
		_chest_menu.visibility_changed.connect(_menu_closed.bind(_chest_menu))
	if walker:
		walker.control = false
		walker.trigger = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_chest_menu.open(pc)
	_huds_for_menus()


func _menu_closed(m: Control) -> void:
	_huds_for_menus()
	if not m.visible:
		if walker:
			walker.control = true
		if _may_capture():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## A station's service: the game's Station Menu (the same as the 2D game's -
## its look, its pages) on tab `tab`, for the station you're docked at.
var _station_menu: Control
var _station_proxy: CosmosStationProxy


func open_service(tab: Variant) -> void:
	if port_station() == null:
		return
	if _station_menu == null:
		_station_proxy = CosmosStationProxy.new()
		add_child(_station_proxy)
		_station_menu = load("res://scenes/ui/station_menu.tscn").instantiate()
		_station_menu.data = CosmosGame.data
		_station_menu.ship = _proxy
		_station_menu.missions = CosmosGame.missions
		_station_menu.quest = CosmosGame.quest
		_menus().add_child(_station_menu)
		_station_menu.visibility_changed.connect(func():
			_huds_for_menus()
			if not _station_menu.visible:
				_bought_first_ship()
				if walker:
					walker.control = true
				ship.apply_upgrades()
				if _may_capture():
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	_station_proxy.setup(port_station())
	if walker:
		walker.control = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_station_menu.open(_station_proxy)
	_station_menu.show_tab(int(tab) if tab is int else 1)
	_huds_for_menus()


# --- Traffic and space combat (stage 4) ------------------------------------------

func _traffic() -> void:
	npc_ships = npc_ships.filter(func(x): return is_instance_valid(x) and not x.dead)
	var f := focus().global_position
	for x in npc_ships:
		if x.global_position.distance_to(f) > TRAFFIC_GONE and x != target and x.rec_id == "":
			x.queue_free()   # (not the economy's own ships: they're its traders, wherever they are here)
	_sync_traders()   # (docked or on foot too: ships keep coming and going)
	if walker or ship.state != "fly" or docked:
		return
	var count := {"trader": 0, "patrol": 0, "pirate": 0, "invader": 0}
	for x in npc_ships:
		count[x.kind] += 1
	var owner := Galaxy.owner_of(system_id)
	var rng := _life_rng

	# Patrols round the nearest station.
	var near_st: CosmosStation = null
	for st: CosmosStation in stations:
		if st.global_position.distance_to(f) < 25000.0:
			near_st = st
	if near_st and count["patrol"] < 2 and owner != "pirates" and CosmosHull.ready("patrol", owner):
		var p := CosmosNpcShip.new()
		p.setup("patrol", self, rng.randi(), owner)
		world.add_child(p)
		p.global_position = near_st.global_position + Vector3(rng.randfn(), rng.randfn() * 0.2, rng.randfn()).normalized() * (near_st.reach + 1500.0)
		p.home = near_st
		npc_ships.append(p)
	# Pirates: now and then, more in lawless systems.
	if count["pirate"] == 0 and _pirate_cd <= 0.0 and CosmosHull.ready("pirate", "pirates"):
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
	if (target is CosmosNpcShip or target is CosmosMonster) and is_instance_valid(target):
		var t = target
		var to: Vector3 = t.global_position - ship.global_position
		if to.normalized().dot(fwd) > 0.93 and to.length() < 3000.0:
			return t.global_position + (t.velocity - ship.velocity) * (to.length() / CosmosBolt.PULSE_SPEED)
	return cam.global_position + fwd * _aim_range(fwd)


## How far along the sights' line (from the camera, through the reticle's middle) the
## shots should meet: the nearest thing on that line - a ship, a monster, a rock, a world,
## a station - else 2.5 km. Fired from the ship below the line, they cross it there: what's
## in the middle of the reticle is what's hit, near or far.
func _aim_range(fwd: Vector3) -> float:
	var o := cam.global_position
	var best := 2500.0
	for b in bodies():
		if not is_instance_valid(b) or b == ship:
			continue
		var to: Vector3 = (b as Node3D).global_position - o
		var along := to.dot(fwd)
		if along < 30.0:
			continue
		var r: float = maxf(radius_of(b), 8.0)
		var off := (to - fwd * along).length()
		if off < r:
			best = minf(best, maxf(along - sqrt(maxf(r * r - off * off, 0.0)), 30.0))   # (where the line enters it)
	return best


func ship_destroyed(s: CosmosNpcShip) -> void:
	npc_ships.erase(s)
	if target == s:
		target = null
	if law:
		law.ship_destroyed(s)
	if s.rec_id != "":   # (a trader of the economy lost: its record gone, its people with it)
		_flown.erase(s.rec_id)
		People.ship_lost(s.rec_id, "Lost with the %s at %s" % [Galaxy.traders.get(s.rec_id, {}).get("name", "ship"), Galaxy.system(system_id).get("name", "?")])
		Galaxy.traders.erase(s.rec_id)
	if s.kind == "invader":
		pass
	elif s.kind == "pirate":
		var b := 400 + _life_rng.randi_range(0, 400)
		bounty += b
		sandbox.add_bounty(b)   # (a voucher: handed in at a station's harbour office)
		note_event("pirate_killed")
		var msg := "Raider destroyed - a bounty voucher for %d dr: hand it in at a station's harbour office" % b
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
	if riding() == s:
		ride_lands(s)   # (you're aboard: it sets you down rather than vanish with you)
		return
	npc_ships.erase(s)
	if s.rec_id != "":
		_flown.erase(s.rec_id)
		Galaxy.traders.get(s.rec_id, {})["live"] = false
	s.queue_free()


# --- The economy's traders, flown here ---------------------------------------------------

var _flown := {}                 # trader id -> its ship here


## Every trader of the economy that's in this system now flown as a ship:
## on its way (along its leg, from where it came in to where it's going) or
## down on a station's lift. Each its own record - its route, its people.
func _sync_traders() -> void:
	for id in _flown.keys():
		if not is_instance_valid(_flown[id]) or (_flown[id] as Node).is_queued_for_deletion():
			_flown.erase(id)   # (its ship gone - back to the economy's own reckoning)
			Galaxy.traders.get(id, {})["live"] = false
	var t0 := Time.get_ticks_usec()
	for id in Galaxy.traders:
		var r: Dictionary = Galaxy.traders[id]
		if _flown.has(id) or str(r.get("system", "")) != system_id:
			continue
		if Time.get_ticks_usec() - t0 > 2000:
			_traffic_t = 0.9   # (a few a frame: the rest a tenth of a second on - no frame spent building them all)
			break
		var emp := str(r.get("empire", ""))
		if not CosmosHull.ready("trader", emp):
			continue   # (its hull still being made: next time)
		var s := CosmosNpcShip.new()
		s.rec_id = str(id)
		s.setup("trader", self, hash(str(id)), emp)
		s.label = "%s - the %s" % [s.label, r["name"]]
		world.add_child(s)
		if r["state"] == "docked":
			var st := _station_by_id(str(r["station"]))
			var p: Dictionary = st.free_pad(s.reach * 1.7) if st else {}
			if st == null or p.is_empty():
				s.queue_free()
				continue
			s.park(st, p)
		else:
			var ends := leg_nodes(r)
			if ends.is_empty():
				s.queue_free()
				continue
			var a: Vector3 = (ends[0] as Node3D).global_position
			var b: Vector3 = (ends[1] as Node3D).global_position
			s.global_position = a.lerp(b, clampf(float(r.get("t", 0.0)), 0.02, 0.98)) + Vector3(0, 120.0, 0)
			s.dest = ends[1]
			s.look_at(b, Vector3.UP)
		r["live"] = true
		_flown[id] = s
		npc_ships.append(s)


func _station_by_id(sid: String) -> CosmosStation:
	for st: CosmosStation in stations:
		if str(st.record.get("id", "")) == sid:
			return st
	return null


func _gate_to(sys: String) -> CosmosGate:
	for g: CosmosGate in gates:
		if g.to == sys:
			return g
	return null


## Where a trader's current leg in this system runs: [from, to] - a station or
## the gate it came in by, its destination or the gate it leaves by. [] if unknown.
func leg_nodes(r: Dictionary) -> Array:
	var legs: Array = r.get("legs", [])
	if legs.is_empty():
		return []
	var start: Node3D = _gate_to(str(r.get("from_sys", ""))) if str(r.get("from_sys", "")) != "" and str(r.get("from_sys", "")) != system_id else null
	if start == null:
		start = _station_by_id(str(r.get("station", "")))
	var end := leg_end(str(r["id"]))
	return [start, end] if start and end else []


## Where a trader's leg in this system ends: the gate on to its next system, or its destination station.
func leg_end(id: String) -> Node3D:
	var r: Dictionary = Galaxy.traders.get(id, {})
	var legs: Array = r.get("legs", [])
	if legs.is_empty():
		return null
	if legs.size() > 1:
		return _gate_to(str(legs[1]["system"]))
	return _station_by_id(str(r.get("dest", "")))


## A trader through a gate: on in the economy - the next system's leg its own.
func trader_jumped(s: CosmosNpcShip) -> void:
	if riding() == s:
		_ride_through(s)   # (you're aboard: on with it)
		return
	npc_ships.erase(s)
	_flown.erase(s.rec_id)
	var r: Dictionary = Galaxy.traders.get(s.rec_id, {})
	if not r.is_empty():
		r["live"] = false
		Galaxy.leg_done(s.rec_id)
	s.queue_free()


## Leaving the system: the traders flown here back to the economy, each where it had got to.
func _release_traders() -> void:
	for id in _flown:
		var s = _flown[id]
		var r: Dictionary = Galaxy.traders.get(id, {})
		if r.is_empty():
			continue
		r["live"] = false
		if is_instance_valid(s) and r["state"] == "travel":
			var ends := leg_nodes(r)
			if not ends.is_empty():   # (positions in the world node: the scene's leaving, out of the tree)
				var a: Vector3 = (ends[0] as Node3D).position
				var b: Vector3 = (ends[1] as Node3D).position
				r["t"] = clampf(((s as Node3D).position - a).dot(b - a) / maxf((b - a).length_squared(), 1.0), 0.0, 0.99)
	_flown = {}


## The ship lost: an explosion, and you back by the first station in a whole ship.
func ship_lost() -> void:
	CosmosBoom.at(self, ship.global_position, 14.0)
	if law:
		law.ship_lost()
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
	if s is CosmosNpcShip and not (s as CosmosNpcShip).pad.is_empty():
		return   # (setting down on a pad, or lifting off one)
	# Never inside your ship: pushed off it (and it off them).
	if ship and ship.state == "fly" and s != ship:
		var dd := s.global_position - ship.global_position
		var need: float = (s.get("reach") if s.get("reach") != null else 12.0) * 0.8 + CosmosShip.HULL_R
		if dd.length() < need and dd.length() > 0.01:
			s.global_position = ship.global_position + dd.normalized() * need
	var r: float = s.get("reach") if s.get("reach") != null else 12.0
	for st: CosmosStation in stations:
		if s.global_position.distance_to(st.global_position) < st.reach + 1500.0:
			s.global_position += st.push_out(s.global_position, r * 0.6)


## A trader's next stop after `from` (another station or planet).
## Where a ship you've stayed aboard goes from station `from`: a hired pilot's
## home world (his town's field), else a world with a town, else another station.
func ride_next(s: CosmosNpcShip, from: Node3D) -> Node3D:
	var home: Variant = s.get_meta("home") if s.has_meta("home") else null
	if is_instance_valid(home) and home is CosmosPlanet and not (home as CosmosPlanet).towns.is_empty():
		return home
	var stops: Array = stations + planets.filter(func(p): return not p.towns.is_empty())
	stops.erase(from)
	return stops[_life_rng.randi() % stops.size()] if not stops.is_empty() else from


## A ship you're aboard come to a world: down on its town's field (a city's if it
## has one), its ramp down for you to walk off - as a hired ride lands. A world
## with no town: on to a station instead.
func ride_lands(s: CosmosNpcShip) -> void:
	var pl := s.dest as CosmosPlanet
	var site: Dictionary = {}
	if pl:
		for t in pl.towns:
			if site.is_empty() or str(t.get("kind", "")) == "city":
				site = t
	if site.is_empty():
		s.dest = ride_next(s, s.dest)
		if s.dest is CosmosPlanet:
			s.dest = stations[0] if not stations.is_empty() else null
		return
	var field: Transform3D = CosmosSandbox.field_of(pl, site)
	s.dest = null
	s._make_gear()
	s.hire = {"state": "in", "t": 0.0, "pl": pl, "field": field, "to": {"pl": pl, "field": field}}
	hud.flash("Coming down on %s's field on %s - walk off down the ramp" % [site.get("name", "the town"), pl.rec.get("name", "")], 4.0)


func trader_next(from: Node3D) -> Node3D:
	var stops: Array = stations + planets.filter(func(p): return p.shape.kind != "gas")
	stops.erase(from)
	return stops[_life_rng.randi() % stops.size()] if not stops.is_empty() else null


# --- Input, the menu ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not built:
		return
	if (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed() and not event.is_echo():
		# (the controls: Keybinds' actions - rebound in Settings > Controls)
		if Keybinds.pressed(event, "pause"):
			if pause_menu and not pause_menu.visible:
				pause_menu.open()
		elif Keybinds.pressed(event, "target"):
			pick_target()
		elif Keybinds.pressed(event, "computer") or Keybinds.pressed(event, "inventory"):
			if _computer and _computer.visible:
				_computer.close()
			else:
				open_computer(0)
		elif Keybinds.pressed(event, "sector_map"):   # (M: the planet's map on a world, else the solar map)
			open_map(0 if walker != null or planet_below(ship.global_position, 3000.0) != null else 1)
		elif Keybinds.pressed(event, "galaxy_map"):
			open_map(2)
		elif Keybinds.pressed(event, "land"):
			if walker == null and _dock.is_empty():
				if ship.state == "fly":
					if not dock_pad.is_empty() or station_near() != null:
						request_dock()   # (near a station: a pad - again: cancel)
					else:
						land()
				elif ship.state == "landed":
					undock() if docked else ship.take_off()
		elif Keybinds.pressed(event, "stand_up"):
			if walker == null and (ship.state == "fly" or (ship.state == "landed" and _dock.is_empty())):
				get_out()   # (up from the seat - landed, docked, or in flight: the ship flies on)
		elif Keybinds.pressed(event, "up"):
			if walker == null and ship.state == "landed" and _dock.is_empty():
				undock() if docked else ship.take_off()
		elif Keybinds.pressed(event, "tool"):
			if walker and walker.deck == null and deposits:
				deposits.toggle_digger()
		elif Keybinds.pressed(event, "ship_call"):
			if walker and walker.deck == null:
				ship_call()
		elif Keybinds.pressed(event, "dock"):
			if walker == null and ship.state == "fly":
				request_dock()
		elif Keybinds.pressed(event, "scan"):
			if walker:
				sandbox.scan()
		elif Keybinds.pressed(event, "drop"):
			if walker:
				sandbox.drop_or_pick()
		elif Keybinds.pressed(event, "tutor"):
			tutor.toggle()
		elif Keybinds.pressed(event, "lock"):
			if walker and walker.deck == null and builds:
				builds.lock_near(walker)
		elif builds and builds.tool_out() and Keybinds.pressed(event, "build_menu"):
			open_build_menu()
		elif builds and builds.tool_out() and Keybinds.pressed(event, "build_rotate"):
			builds.turn_piece()
		elif builds and builds.tool_out() and Keybinds.pressed(event, "build_mode"):
			builds.next_mode()
		elif builds and builds.tool_out() and Keybinds.pressed(event, "build_snap"):
			builds.toggle_snap()
	elif event is InputEventMouseButton and event.pressed and builds and builds.tool_out() and not free_mouse and Keybinds.pressed(event, "build_rotate"):
		builds.turn_piece()   # (the middle button: the builder's piece turned)
	elif event is InputEventMouseButton and not (pause_menu and pause_menu.visible) and _toggle_click(event):
		pass   # (a right click: the mouse freed / captured again)
	elif event is InputEventMouseButton and free_mouse and not (pause_menu and pause_menu.visible):
		_free_click(event)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not (pause_menu and pause_menu.visible):
		if event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _may_capture():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif walker:
			# (the left click on foot: what's in reach - a person, a terminal, a seat, the
			# pilot's seat, a package - else the rifle / the mining beam)
			if event.pressed and not (builds and builds.tool_out()) and interact():
				walker.trigger = false
			else:
				walker.trigger = event.pressed
		else:
			ship.trigger = event.pressed


## The 2D game's HUD over the 3D view (the same look): the health gauge
## (hull, shields, fuel - on foot the automaton's health), the toolbar, the
## event console, messages (no minimap: the markers in the view instead);
## Tab opens the Automaton; the tutorial's icon opens its book there.
## CosmosMapMirror keeps the system's 2D stand-ins for the Automaton's
## maps and the missions.
var hud2d: CanvasLayer
var _mirror: CosmosMapMirror


func _build_game_hud() -> void:
	_proxy = CosmosShipProxy.new()
	_proxy.cosmos = self
	add_child(_proxy)
	_mirror = CosmosMapMirror.new()
	_mirror.cosmos = self
	add_child(_mirror)
	hud2d = load("res://scenes/ui/hud.tscn").instantiate()
	hud2d.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(hud2d)
	hud2d.bind(_proxy, CosmosGame.data)
	hud2d.toolbar.slot_pressed.connect(_use_slot)
	hud2d.hint.visible = false   # (the 2D game's click-to-fly hints: not here - the tutorial's icon instead)
	hud2d.gauge.shape_source = func(): return ProcArt.get_tex("ship_player")
	if hud2d.mining_panel:
		hud2d.mining_panel.process_mode = Node.PROCESS_MODE_DISABLED   # (no mining in the 3D game yet)
		hud2d.mining_panel.visible = false
	# Bottom right, icons (each its key over it): the Automaton's inventory, the three maps, the tutorial (its book in the Archive).
	var icons := [["InventoryButton", "ui_cargo", "Inventory", "Tab", "Your inventory, your toolbar and your automaton's equipment.", func(): open_computer(0)],
		["PlanetMapButton", "planets", "Planet map", "M", "The world you're on or nearest, as a globe (M on a planet).", func(): open_map(0)],
		["SolarMapButton", "ui_system", "Solar map", "M", "The system you're in, in 3D (M off a planet).", func(): open_map(1)],
		["GalaxyMapButton", "ui_galaxy", "Galaxy map", "G", "The galaxy in 3D.", func(): open_map(2)],
		["TutorialButton", "help", "Tutorial", "", "The tutorial: how to play - in the Automaton's Archive.", open_tutorial]]
	for i in icons.size():
		var ic: Array = icons[i]
		var right := -16.0 - (icons.size() - 1 - i) * 56.0
		_hud_icon(ic[0], ic[1], EditorIcons.tip(ic[2], ic[3], ic[4]), str(ic[3]), Rect2(right - 48.0, -64.0, 48.0, 48.0), ic[5])


## An icon button at the HUD's bottom right (`r`: its offsets from that corner), its key written over it.
func _hud_icon(id: String, icon: String, tip: String, key: String, r: Rect2, act: Callable) -> void:
	var b := Button.new()
	b.name = id
	EditorIcons.dress(b, icon, tip)
	b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	b.offset_left = r.position.x
	b.offset_top = r.position.y
	b.offset_right = r.end.x
	b.offset_bottom = r.end.y
	b.pressed.connect(act)
	b.text = ""
	b.expand_icon = true
	hud2d.add_child(b)
	if key == "":
		return
	var l := Label.new()
	l.name = id + "Key"
	l.text = key
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", NeonTheme.CYAN)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	l.offset_left = r.position.x - 8.0
	l.offset_right = r.end.x + 8.0
	l.offset_top = r.position.y - 24.0
	l.offset_bottom = r.position.y - 2.0
	hud2d.add_child(l)


## The Automaton open on its MAP tab's map `sub` (0 the planet's, 1 the solar system's, 2 the galaxy's).
func open_map(sub: int) -> void:
	var tab: int = load("res://scripts/ui/ship_menu.gd").MAP_TAB
	open_computer(tab)
	_computer.show_tab(tab, sub)


func open_tutorial() -> void:
	var archive: int = load("res://scripts/ui/ship_menu.gd").ARCHIVE_TAB
	open_computer(archive)
	var arch: Node = _computer.page(archive)
	if arch and arch.has_method("open_book"):
		arch.open_book("tutorial")


## A toolbar slot: what's on it used (an energy drink...).
func _use_slot(i: int) -> void:
	var slot: Dictionary = hud2d.toolbar.slot_at(i)
	var id := str(slot.get("id", ""))
	if id != "":
		hud.flash(Items.display_name(id))


## The 2D HUD's gauge on what you are: the ship, or you on foot.
const AUTOMATON_OUTLINE := "res://art/player/player_idle_s.png"


func _gauge_on_walker(on: bool) -> void:
	if hud2d == null or hud2d.gauge == null:
		return
	var g: HealthGauge = hud2d.gauge
	if on:
		g.which = "automaton"
		var outline: Texture2D = load(AUTOMATON_OUTLINE) if ResourceLoader.exists(AUTOMATON_OUTLINE) else null
		g.shape_source = func(): return outline   # (the automaton's outline, as the 2D game's surface gauge)
		g.silhouette = outline
		g.hull_name = "HEALTH"
		g.shield_name = "SHIELD"
		g.read = func(): return [walker.hp, CosmosWalker.MAX_HP, walker.shield, walker.max_shield] if is_instance_valid(walker) else [100.0, 100.0, 60.0, 60.0]   # (its shield the ring round it, as the ship's)
		g.fuel = func(): return [CosmosGame.data.stamina, Stamina.MAX, 0.0]
		g.fuel_name = "Stamina"
	else:
		g.which = "ship"
		g.shape_source = func(): return ProcArt.get_tex("ship_player")
		g.silhouette = ProcArt.get_tex("ship_player")
		g.hull_name = "HULL"
		g.shield_name = "SHIELDS"
		g.read = func(): return [ship.hull, ship.max_hull, ship.shield, ship.max_shield]
		g.fuel = func(): return [CosmosGame.data.fuel_level(), CosmosGame.data.fuel_max(), Shipyard.FUEL_JUMP]
		g.fuel_name = "Fuel"
	g.refresh()


## The mouse is captured for steering - not in a test, a tour or a bot's window.
## Out of the window (Alt+Tab, another window clicked): the mouse let go - the
## ship and the camera read it only while it's captured; a click back in captures it again.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if ship:
			ship.trigger = false
		if walker:
			walker.trigger = false


func _may_capture() -> bool:
	return DisplayServer.get_name() != "headless" and not Settings.bot_arg() and DisplayServer.window_is_focused() and not free_mouse   # (never grabbed while you're in another window, or the mouse is free)


# --- The free mouse ----------------------------------------------------------------

## The free mouse ("free_mouse": a right click; again: captured again - a right
## click, not a drag: held and dragged the right button still turns the camera):
## the cursor shown and the mouse yours - a click ("pointer") selects what's under
## it (your target), held and dragged it steers the ship / turns your view as the
## captured mouse does. Kept from system to system.
static var free_mouse := false
const DRAG_PX := 6.0
var _press := ""                 # (the button held: "pointer" - a click or a drag)
var _press_at := Vector2.ZERO
var _dragging := false
var _toggle_held := false        # (the free mouse's button down: a click toggles it, a drag doesn't)
var _toggle_moved := 0.0


func set_free_mouse(on: bool) -> void:
	free_mouse = on
	_press = ""
	_dragging = false
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if ship:
			ship.trigger = false
		if walker:
			walker.trigger = false
	elif _may_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.flash("Mouse free - right click captures it again" if on else "Mouse captured")


## The ship and the camera read the mouse's motion: captured - or free and dragged.
func mouse_steers() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or (free_mouse and _dragging)


func _input(event: InputEvent) -> void:
	# (before the ship and the camera see it: a press moved far enough is a drag - they steer with it)
	if free_mouse and _press == "pointer" and not _dragging and event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).position.distance_to(_press_at) > DRAG_PX:
			_dragging = true
	if _toggle_held and event is InputEventMouseMotion:
		_toggle_moved += (event as InputEventMouseMotion).relative.length()


## The free mouse's button (a right click): down - noted; up again without a drag -
## the mouse freed, or captured again. True if it was that button.
func _toggle_click(event: InputEventMouseButton) -> bool:
	if event.pressed and Keybinds.pressed(event, "free_mouse"):
		_toggle_held = true
		_toggle_moved = 0.0
		return true
	if not event.pressed and _toggle_held and event.is_action_released("free_mouse"):
		_toggle_held = false
		if _toggle_moved <= DRAG_PX:
			set_free_mouse(not free_mouse)
		return true
	return false


func _free_click(event: InputEventMouseButton) -> void:
	if Keybinds.pressed(event, "pointer"):
		_press = "pointer"
		_press_at = event.position
		_dragging = false
	elif not event.pressed and _press != "":
		var click := not _dragging and event.position.distance_to(_press_at) <= DRAG_PX
		_press = ""
		_dragging = false
		if click and event.is_action_released("pointer"):
			var b := body_at(event.position)
			if b != null:
				target = b
				hud.flash("Target: %s" % label_of(b))


## The body (planet, station, gate, ship...) under the screen point `at`, or null:
## the one whose middle is nearest it, within its size on the screen (28 px at least).
func body_at(at: Vector2) -> Node3D:
	var best: Node3D = null
	var bd := INF
	var per_m := get_viewport().get_visible_rect().size.y * 0.5 / tan(deg_to_rad(cam.fov) * 0.5)
	for b: Node3D in bodies():
		if not is_instance_valid(b) or b == ship or cam.is_position_behind(b.global_position):
			continue
		var d := maxf(cam.global_position.distance_to(b.global_position), 1.0)
		var r := maxf(radius_of(b) / d * per_m, 28.0)
		var off := cam.unproject_position(b.global_position).distance_to(at)
		if off < r and off / r < bd:
			bd = off / r
			best = b
	return best


## Esc: the game's own pause menu (the title screen's, over the game: Resume,
## Save, Load, Settings, Talos, Quit to menu, Exit).
var pause_menu: Control


func _build_pause_menu() -> void:
	var pl := CanvasLayer.new()
	pl.name = "PauseLayer"
	pl.layer = 50
	pl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pl)
	pause_menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	pause_menu.overlay = true
	pause_menu.visible = false
	pl.add_child(pause_menu)
	pause_menu.visibility_changed.connect(func():
		var on: bool = pause_menu.visible
		ship.control = not on and walker == null
		if walker:
			walker.control = not on
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on or not _may_capture() else Input.MOUSE_MODE_CAPTURED)


func _exit_tree() -> void:
	_release_traders()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
