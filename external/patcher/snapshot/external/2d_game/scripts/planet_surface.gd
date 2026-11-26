extends Node2D
## A planet surface in isometric view. Generated from the planet's seed:
## terrain (TileMapLayer with a procedurally painted tile atlas), a Minoan
## palace and village houses built from the Minoan tile set (MinoanTiles),
## Minoan citizens, scenery and your
## landed ship. Walk with the mouse (click or hold), click things to interact,
## click your ship or "Leave Planet" to return to space.
##
## The space game is kept in SaveGame.space_state while you're down here;
## loot is written into it, and taking off restores it.

const N := 440                      # map is N x N tiles (streamed: see "Streaming"; was 880 - a quarter of the area since 2026-11-09)
## Streaming: the planet is generated whole on a worker thread (heights,
## terrain, the villages' plans) but its contents are only made near you:
## scenery per CHUNK x CHUNK tiles within LOAD_R chunks (freed beyond
## UNLOAD_R), buildings and citizens within BUILD_R tiles, and the path-finding
## grid over a NAV_WIN-tile window that follows you (rebuilt on a worker thread).
const CHUNK := 16
const LOAD_R := 2
const UNLOAD_R := 4
const BUILD_R := 64
const NAV_WIN := 96
const NAV_SHIFT := 24
const TILE := Vector2i(128, 64)
const INTERACT_RANGE := 80.0
const PROPS := preload("res://scripts/surface_props.gd")
const MINIMAP := preload("res://scripts/surface_minimap.gd")

var planet_id := ""
var pdata: Dictionary
var state: Dictionary               # the space game snapshot (save format)

var tilemap: TileMapLayer
var objects: Node2D                 # y-sorted
var pilot: Node2D
var lander: Node2D
var buildings: Array = []          # BuiltBuilding (explorable, made from tiles)
var npcs: Array = []            # Minoan citizens (MinoanNpc: guards and androids)
var creatures: Array = []       # wildlife around you (SurfaceCreature; see _stream_fauna)

var _terrain: PackedInt32Array      # terrain index per cell
var _height: PackedFloat32Array     # raw height per cell (-1..1), for the ground shader
var _rock: PackedByteArray          # solid ground per cell (0..255; crags and cliffs; solid where the filtered value >= ROCK_SOLID)
var _crag: PackedByteArray          # crags (their look and height; _rock also has the cliffs)
var _ramp: PackedFloat32Array       # 0..1: ledges meet in a slope here, not a cliff (SurfaceTerrain.terrace)
var _elev: PackedFloat32Array       # px the ground is raised per cell (SurfaceTerrain.elevation)
var _cliff: PackedByteArray         # tiles a cliff runs through (_mark_cliffs)
const TERRAIN := preload("res://scripts/surface_terrain.gd")
const TTILES := preload("res://scripts/terrain_tiles.gd")
## Tiled ground (pdata "tiles": TerrainTiles): levels, ramps, the plots' level.
var _tiled := false
var _lvl := PackedByteArray()
var _rampd := PackedByteArray()
var _plot_lvl := 0
var _world_to_grid: Transform2D
var _g2w: Transform2D               # grid -> world (thread-safe _cell_pos)
var floor_layer: TileMapLayer       # building floors (procedural floor tiles)
var _floor_sources := {}
var _blocked_cells := {}            # building footprints (+1 margin): no scenery
var _occluders: Array = []          # wall tiles and columns that fade in front of you
var _tall_props := {}               # trees, palms, crystals, boulders (also fade): prop -> true
var _prop_buckets := {}             # tile cell / 4 -> tall props there (fast fade lookups)
var _faded: Array = []              # tall props currently faded (or fading back)
var _props := {}                    # all scenery (Prop nodes and flat PropData): prop -> true
var _decor: Node2D                   # flat ground cover: one PropBatch per chunk
var _decor_batches := {}
var _height_img: Image
var _height_tex: ImageTexture
var _minimap: Control
var _layout := {}
var surface_map: SurfaceMap   # full map (M)
var field_menu: Control        # the Field Computer (Tab): quest, inventory, bestiary... (field_menu.gd)
var toolbar: SurfaceToolbar    # the toolbar on foot (1-3)
const FIELD_MENU := preload("res://scripts/field_menu.gd")
var level_editor: LevelEditor
const PROP_KINDS := ["tree", "palm", "bush", "tuft", "flowers", "rock", "boulder", "pebbles", "crystal", "shard"]
var _door_zones: Array = []         # [world point, radius]: kept free of scenery
var _astar: AStarGrid2D             # navigation grid (NAV_S points per tile)
var _nav_comp := PackedInt32Array()  # each nav point's region (-1 solid): no path between regions
## Path searches this frame and their time (the creatures share a budget: CREATURE_PATHS a frame).
var path_calls := 0
var path_us := 0
var creature_paths := 0
const CREATURE_PATHS := 2
var _nav_from_grid: Transform2D     # nav grid coords -> world
var _repath_t := 0.0
## Camera zoom (mouse wheel): target value, eased toward each frame.
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.5
const ZOOM_STEP := 1.12
var _zoom := 1.0
const NAV_S := 4
## Nav points this close to a wall are solid. With 4 points per tile every
## nav point beside a wall is ~7.2 px from it, on both sides - so this must be
## more than that, or the grid can step straight through walls. Doorways are
## re-opened explicitly afterwards (_open_doorways).
const NAV_CLEAR := 8.0
var _rng := RandomNumberGenerator.new()
var _target_thing: Node2D = null
var _hovered: Node2D = null
## The floor the pilot is on: 0 the ground, 1 the upper floor of level_b.
var level := 0
var level_b: BuiltBuilding
var _climbing := false
var _pending_target: Array = []     # [point, floor, building] to reach after the stairs
var _holding := false
var _pad_walk := false   # walking by the gamepad's left stick
var _press_ms := 0
var _last_mouse := Vector2.ZERO

# HUD
var _hud: CanvasLayer
var _credits_label: Label
var _prompt: Label
var _prompt_tween: Tween
@onready var pause_menu: Control = $PauseLayer/PauseMenu


func _ready() -> void:
	add_to_group("hot_buildings")   # (LiveLink: reskin_buildings when the tiles change)
	RenderingServer.frame_pre_draw.connect(_apply_lifts)
	if prebuilding:
		process_mode = Node.PROCESS_MODE_DISABLED   # its things stay still until shown
	else:
		NeonTheme.set_empire(Galaxy.owner_of(Galaxy.current_system))
	if planet_override != "":
		planet_id = planet_override   # (built ahead from space, before you land: main.gd _prebuild)
	else:
		planet_id = SaveGame.landed_planet if SaveGame.landed_planet != "" else "thalassa"
	pdata = Planets.get_planet(planet_id)
	state = state_override if not state_override.is_empty() else SaveGame.space_state
	# (its pictures first in the background loading: never one loaded on the spot here)
	if pdata.has("tiles"):
		ProcArt.prefetch(["tile_%s_" % str(pdata["tiles"]), "creature_%s_" % str(pdata["tiles"]), "tile_%s_" % _culture_prefix(), "tile_palace_", "tile_", "npc_"])
	if state.is_empty():  # started directly (testing): minimal state
		state = {"player": {"credits": 150, "items": {}, "equipment": ["laser"], "tech": []}}
	if not state.has("planets"):
		state["planets"] = {}
	if not state["planets"].has(planet_id):
		state["planets"][planet_id] = {}
	_rng.seed = pdata["seed"]
	_tiled = pdata.has("tiles")
	_sky = _tiled and TTILES.is_sky(str(pdata["tiles"]))

	# Built in small steps (heavy parts on worker threads), so whatever is on
	# screen keeps animating: when landing, the space scene builds this hidden
	# (prebuilding) during the ship's landing animation, then switches to it.
	_loading = true
	MinoanTiles.culture = culture()   # (its buildings: the holding empire's own pieces, if it has them)
	set_process(false)
	set_process_unhandled_input(false)
	set_process_input(false)
	visible = false
	_slice_t = Time.get_ticks_usec()
	await _step(0.05, "terrain")
	_build_background()
	_build_tilemap()
	_layout = DataFiles.read(_layout_path())
	if _tiled and _layout.is_empty():
		await _begin_streamed()   # (made a chunk at a time, nearest first - SurfacePlanner)
		await _await_pad_area()
		await _stream_plans(true)   # (the pad's village: its buildings, if their pictures are in)
		await _stream_initial()     # (the pad's scenery and the path-finding window)
	else:
		await _build_whole()
	_theme_buildings()
	await _step(0.95, "hud")
	_build_hud()
	damage_screen = DamageScreen.new()   # (near death: the window fails like a broken monitor)
	damage_screen.health = func(): return pilot.hp / maxf(1.0, pilot.max_hp) if pilot and pilot.hp > 0.0 else 1.0
	add_child(damage_screen)
	_loading = false
	build_progress = 1.0
	# (its layers listed now, while it's hidden: searching 5000+ nodes for them
	# was a few ms of the frame the world appears in - show_world)
	_layers = find_children("*", "CanvasLayer", true, false)
	is_built = true
	built.emit()
	if discard:
		UI.dismantle(self)   # (built ahead and no longer wanted: taken apart a few ms a frame)
		return
	if not prebuilding:
		show_world()


## Leaving (or freed mid-build): worker tasks read this surface - let them finish first.
# --- Streaming the planet (tiled planets): a chunk at a time --------------------------------

## The planet is made by a SurfacePlanner on a worker thread, one job at a time:
## first its plan (villages, gates, bands - only the terrain near them made),
## then GEN x GEN chunks, the nearest to you first, for as long as you're here.
## Each chunk's arrays, tiles and map pixels are taken in a few ms a frame
## (_pump_gen: tied to the tree's frames - a planet built ahead, hidden and still,
## streams too). Until a chunk's in, its ground is the placeholder plate (the
## planet's ground colour) and can't be walked on; scenery, buildings, gates,
## people and animals come out only where their chunk is in.
var _streamed := false
var _planner: SurfacePlanner
var _planned := false
var _gen_result = null               # (what the worker job made - read once it's done)
var _gen_done := PackedByteArray()   # per chunk: 1 in
var _gen_busy := {}                  # chunk index -> true (on the worker or being taken in)
var _take_q: Array = []              # chunk results being taken in: {res, step, t}
var _tlayers := {}                   # (level * 2 + y-sorted) -> TileMapLayer
var _flat := PackedByteArray()       # per tile source: 1 a flat tile (unsorted layer)
var _map_dirty := false
var _map_t := 0.0
var _gen_count := 0
const GEN := SurfacePlanner.GEN
const GEN_N := (N + GEN - 1) / GEN
const TAKE_US := 2500                # main thread a frame for taking chunks in (built ahead: TAKE_BG_US)
const TAKE_BG_US := 1000
const BG_GEN_GAP_MS := 40
var _gen_at := 0
const TILES_A_STEP := 500            # tiles set on the layers in one go
## Chunks made round you (in chunks: ~115 tiles - past the buildings' BUILD_R and
## the scenery's reach); farther ones only when you go there or they're asked for.
const STREAM_R := 3.6


func _begin_streamed() -> void:
	_streamed = true
	_tile_set_id = str(pdata["tiles"])
	_tile_pieces = TTILES.ground_pieces(_tile_set_id)
	_th = PackedFloat32Array(pdata["thresholds"])
	_walk_t = PackedByteArray()
	for t in pdata["terrain"]:
		_walk_t.append(1 if t[2] else 0)
	_height = PackedFloat32Array()
	_height.resize(N * N)
	_ramp = PackedFloat32Array()
	_ramp.resize(N * N)
	_terrain = PackedInt32Array()
	_terrain.resize(N * N)
	for a in ["_rock", "_crag", "_lvl", "_rampd"]:
		var b := PackedByteArray()
		b.resize(N * N)
		set(a, b)
	_gen_done.resize(GEN_N * GEN_N)
	_flat.resize(_tile_pieces.size())
	for i in _tile_pieces.size():
		var base := str(_tile_pieces[i]).substr(3)
		_flat[i] = 1 if base in TTILES.FLAT or base in TTILES.RIMS else 0
	_build_placeholder()
	_make_tile_holder()
	_map_img = Image.create(N, N, false, Image.FORMAT_RGB8)
	_map_img.fill(Color(0.02, 0.025, 0.04))
	map_tex = ImageTexture.create_from_image(_map_img)
	_setup_fog()
	objects = Node2D.new()
	objects.y_sort_enabled = true
	add_child(objects)
	_place_pad()
	# The planner: its plan first (the set's ground pieces wanted for the tile set -
	# loaded in the background, the game going on meanwhile).
	_planner = SurfacePlanner.new()
	_planner.pdata = pdata
	_planner.planet_id = planet_id
	_planner.seed_ = int(pdata["seed"])
	_planner.tile_set_id = _tile_set_id
	_planner.tile_pieces = _tile_pieces
	_planner.culture_name = _culture_name()
	_planner.sky = _sky
	_planner.g2w = _g2w
	get_tree().process_frame.connect(_pump_gen)
	# (its pictures asked for first - never waited for: one not in yet is drawn
	# as its placeholder, made again in place when it's in - ProcArt / TerrainTiles.refresh)
	ProcArt.prefetch(["tile_%s_" % _tile_set_id, "tile_"])
	TTILES.prefetch(_tile_pieces)
	build_stage = "Planning its villages, gates and wilds"
	_gen_task = WorkerThreadPool.add_task(func():
		_planner.setup()
		_planner.plan()
		_planner.atlas_looks = _sample_looks()
		_planner.tile_ts = TTILES.tile_set(_tile_pieces)
		TTILES.predecode(_tile_set_id)
		_gen_result = "plan", false, "Planet plan")


## Where the ground isn't made yet: a plate of the planet's ground colour under
## the tiles (the real ground covers it chunk by chunk).
func _build_placeholder() -> void:
	var col: Color = pdata["terrain"][mini(_first_walkable(), pdata["terrain"].size() - 1)][1]
	var e := 0.5
	var poly := Polygon2D.new()
	poly.name = "Placeholder"
	poly.polygon = PackedVector2Array([_g2w * Vector2(-e, -e), _g2w * Vector2(N - e, -e), _g2w * Vector2(N - e, N - e), _g2w * Vector2(-e, N - e)])
	poly.color = col.darkened(0.45)
	poly.z_index = -12
	add_child(poly)


## Built enough to stand in: every chunk under the path-finding window round
## the pad in (the rest streams on as you go).
func _await_pad_area() -> void:
	var c := Vector2i(N / 2, N / 2)
	var area := _nav_window(_nav_origin_for(c))
	var lo := area.position / GEN
	var hi := (area.end - Vector2i.ONE) / GEN
	var total := (hi.x - lo.x + 1) * (hi.y - lo.y + 1)
	while is_inside_tree() and not gen_ready_rect(area):
		var n := 0
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				n += _gen_done[x * GEN_N + y]
		build_progress = maxf(build_progress, lerpf(0.1, 0.9, float(n) / total))
		await get_tree().process_frame


func _first_walkable() -> int:
	for t in pdata["terrain"].size():
		if pdata["terrain"][t][2]:
			return t
	return 0


func _make_tile_holder() -> void:
	# The ground as 3D geometry (Ground3D: made once the tile set's there - when
	# the world's planned) - else the tile layers, drawn as pictures.
	if Ground3D.enabled:
		if _tile_ts == null:
			return
		var g3 := Ground3D.new()
		if g3.setup(self, _tile_ts, _tile_pieces, _plot_lvl):
			ground3d = g3
			add_child(g3)
			return
		g3.free()
	var holder := Node2D.new()
	holder.name = "TileGround"
	holder.z_index = -10
	if GroundChunks.enabled:
		ground_chunks = GroundChunks.new()
		add_child(ground_chunks)
		ground_chunks.host(holder)
	else:
		add_child(holder)
	tile_ground = holder


## Your ship on the pad and you beside it - at once, before anything's made.
func _place_pad() -> void:
	var center := Vector2i(N / 2, N / 2)
	lander = PROPS.Lander.new()
	var pl: Dictionary = state.get("player", {})
	lander.ship_class = str(pl.get("ship_class", "player"))
	lander.look = pl.get("ship_look", {})
	lander.position = _cell_pos(center)
	objects.add_child(lander)
	pilot = PROPS.Pilot.new()
	pilot.surface = self
	pilot.stamina = Stamina.of(state["player"])
	Skills.state(state["player"])       # (its skills: made the first time, the starting ones on the toolbar)
	Sfx.warm("skill")
	refresh_gear()
	pilot.position = _cell_pos(center) + Vector2(0, 90)
	var at: Array = SaveGame.resume.get("pos", []) if str(SaveGame.resume.get("planet", "")) == planet_id else []
	if at.size() == 2:
		pilot.position = Vector2(float(at[0]), float(at[1]))
	SaveGame.resume = {}
	objects.add_child(pilot)
	var cam := Camera2D.new()
	cam.enabled = not prebuilding
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	pilot.add_child(cam)


func _gen_index(c: Vector2i) -> int:
	return clampi(c.x / GEN, 0, GEN_N - 1) * GEN_N + clampi(c.y / GEN, 0, GEN_N - 1)


## The ground at a cell made and in (always, on a planet built whole).
func gen_ready(c: Vector2i) -> bool:
	if not _streamed:
		return true
	if c.x < 0 or c.y < 0 or c.x >= N or c.y >= N:
		return false
	return _gen_done[_gen_index(c)] == 1


## Every chunk under `r` in.
func gen_ready_rect(r: Rect2i) -> bool:
	if not _streamed:
		return true
	var a := r.intersection(Rect2i(0, 0, N, N))
	for x in range(a.position.x / GEN, (a.end.x - 1) / GEN + 1):
		for y in range(a.position.y / GEN, (a.end.y - 1) / GEN + 1):
			if _gen_done[x * GEN_N + y] == 0:
				return false
	return true


## Everything within reach made and placed: the ground round you, its scenery.
func streaming_idle() -> bool:
	return (not _streamed or (_planned and _take_q.is_empty() and _gen_task < 0 and _next_chunk() < 0)) \
		and _chunk_tasks.is_empty() and _place_queue.is_empty()


## How far the streaming is: [chunks in, of all] (the loading bar).
func gen_progress() -> Vector2i:
	return Vector2i(_gen_count, GEN_N * GEN_N)


## The ground round you: [chunks in, of all within reach (STREAM_R)] - the loading console's bar.
func near_progress() -> Vector2i:
	if not _streamed or pilot == null:
		return Vector2i(1, 1)
	var hc := Vector2(_cell_at(pilot.position)) / GEN
	var out := Vector2i.ZERO
	for idx in GEN_N * GEN_N:
		if Vector2(idx / GEN_N + 0.5, idx % GEN_N + 0.5).distance_squared_to(hc) < STREAM_R * STREAM_R:
			out.y += 1
			out.x += _gen_done[idx]
	return out


## Each frame: the worker's next job started (the nearest chunk not made), what
## it made taken in - within a few ms.
func _pump_gen() -> void:
	if not is_inside_tree() or discard:
		return
	if ground3d and not is_processing():      # (built ahead, hidden: its ground's meshes still come in)
		ground3d.collect(6)
	if _gen_task >= 0 and WorkerThreadPool.is_task_completed(_gen_task):
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1
		var res = _gen_result
		_gen_result = null
		if res is String and res == "plan":
			_apply_plan()
		elif res is Dictionary:
			_take_q.append({"res": res, "step": 0})
	# (built ahead: a chunk job every BG_GEN_GAP_MS at most - the worker threads
	# are the game's too; landing or landed: as fast as they come)
	if _gen_task < 0 and _planned and _take_q.size() < 2 and (not background or Time.get_ticks_msec() - _gen_at >= BG_GEN_GAP_MS):
		_gen_at = Time.get_ticks_msec()
		var next := _next_chunk()
		if next >= 0:
			_gen_busy[next] = true
			var cx := next / GEN_N
			var cy := next % GEN_N
			_gen_task = WorkerThreadPool.add_task(func(): _gen_result = _planner.chunk(cx, cy), false, "Planet chunk")
	var budget := 0
	if not _take_q.is_empty():
		budget = BgWork.take() if background else (TAKE_BG_US if prebuilding else TAKE_US)   # (built ahead: the paced share)
	var t0 := Time.get_ticks_usec()
	while not _take_q.is_empty() and Time.get_ticks_usec() - t0 < budget:
		if _take_step(_take_q[0]):
			_take_q.pop_front()
	_map_t -= get_process_delta_time()
	if _map_dirty and _map_t <= 0.0:
		_map_t = 0.25
		_map_dirty = false
		map_tex.update(_map_img)
	if _take_q.is_empty() and _gen_task < 0:
		build_stage = ""   # (all round you's in)


## Areas asked for (stream_area): their chunks before the ones near you.
var _want_areas: Array = []


## Waits until every chunk under `area` (cells) is in - made first.
func stream_area(area: Rect2i) -> void:
	if not _streamed:
		return
	var a := area.intersection(Rect2i(0, 0, N, N))
	_want_areas.append(a)
	while is_inside_tree() and not gen_ready_rect(a):
		await get_tree().process_frame
	_want_areas.erase(a)


## The whole planet in (tests: what the planet holds everywhere).
func stream_all() -> void:
	await stream_area(Rect2i(0, 0, N, N))


## Where you were when nothing near was left to make (the search skipped till you move).
var _idle_at := Vector2i(-1, -1)


func _next_chunk() -> int:
	for a in _want_areas:
		var hc0 := Vector2(a.get_center()) / GEN
		var best0 := -1
		var bd := INF
		for x in range(a.position.x / GEN, (a.end.x - 1) / GEN + 1):
			for y in range(a.position.y / GEN, (a.end.y - 1) / GEN + 1):
				var idx := x * GEN_N + y
				if _gen_done[idx] == 1 or _gen_busy.has(idx):
					continue
				var d := Vector2(x + 0.5, y + 0.5).distance_squared_to(hc0)
				if d < bd:
					bd = d
					best0 = idx
		if best0 >= 0:
			return best0
	var here := _cell_at(pilot.position) if pilot else Vector2i(N / 2, N / 2)
	var hc := Vector2(here) / GEN
	var at := Vector2i(hc * 4.0)   # (a quarter chunk: no new search until you've moved that far)
	if _want_areas.is_empty() and at == _idle_at:
		return -1   # (all round you's in: nothing to look for each frame)
	var best := -1
	var best_d := STREAM_R * STREAM_R   # (only what's near you: the rest when you go there)
	for idx in GEN_N * GEN_N:
		if _gen_done[idx] == 1 or _gen_busy.has(idx):
			continue
		var d := Vector2(idx / GEN_N + 0.5, idx % GEN_N + 0.5).distance_squared_to(hc)
		if d < best_d:
			best_d = d
			best = idx
	_idle_at = at if best < 0 and _want_areas.is_empty() else Vector2i(-1, -1)
	return best


## The plan's in: the villages, gates and bands to stream, the planet's levels.
func _apply_plan() -> void:
	var p := _planner
	_plans = p.plans
	_npc_plans = p.npc_plans
	_plot_cells = p.plot_cells
	_clear_spots = p.clear_spots
	gates = p.gates
	_village_spots = p.village_spots
	_industry = p.industry
	_fauna_plans = p.village_fauna.duplicate()
	_atlas_looks = p.atlas_looks
	_water_top = p.water_top
	_site_h = p.site_h
	_plot_lvl = p.plot_lvl
	_tile_ts = p.tile_ts
	if tile_ground == null and ground3d == null:
		_make_tile_holder()      # (the 3D ground, now its tile set's here)
	_planned = true
	build_stage = "Making its ground, chunk by chunk"
	AssetPool.note("%s: planned - %d villages, %d gates, %d pirates" % [str(pdata.get("name", "")), _village_spots.size(), gates.size(), _npc_plans.filter(func(q): return str(q.get("kind", "")) == "pirate").size()])
	# The cube's brick sides under the rim (at the water's level).
	var e := 0.5
	var edge := Node2D.new()
	edge.set_script(preload("res://scripts/surface_edge.gd"))
	var up := Vector2(0, _plot_lvl * TTILES.LEVEL_PX)
	edge.corners = [_g2w * Vector2(-e, N - e) + up, _g2w * Vector2(N - e, N - e) + up, _g2w * Vector2(N - e, -e) + up]
	edge.z_index = -11
	add_child(edge)
	_build_prop_atlas()


## One step of taking a chunk in (true: it's all in): its arrays and map
## pixels, then its tiles TILES_A_STEP at a time, then it's ready.
func _take_step(item: Dictionary) -> bool:
	var res: Dictionary = item["res"]
	var r: Rect2i = res["rect"]
	if item["step"] == 0:
		var hh: PackedFloat32Array = res["height"]
		var tt: PackedByteArray = res["terrain"]
		var rp: PackedFloat32Array = res["ramp"]
		var ll: PackedByteArray = res["lvl"]
		var rd: PackedByteArray = res["rampd"]
		for a in r.size.x:
			for b in r.size.y:
				var k := (r.position.x + a) * N + r.position.y + b
				var o := a * r.size.y + b
				_height[k] = hh[o]
				_terrain[k] = tt[o]
				_ramp[k] = rp[o]
				_lvl[k] = ll[o]
				_rampd[k] = rd[o]
		_map_img.blit_rect(res["map"], Rect2i(Vector2i.ZERO, r.size), r.position)
		_map_dirty = true
		item["step"] = 1
		item["t"] = 0
		return false
	var tiles: PackedInt32Array = res["tiles"]
	var from: int = item["t"]
	var to := mini(from + TILES_A_STEP * 4, tiles.size())
	if ground3d:         # (3D: the chunk's tiles become a mesh, worked out on a worker)
		ground3d.add_chunk(_gen_index(r.position), tiles, r)
		to = tiles.size()
	else:
		for e in range(from, to, 4):
			_tile_layer(tiles[e], _flat[tiles[e + 3]] == 0).set_cell(Vector2i(tiles[e + 1], tiles[e + 2]), tiles[e + 3], Vector2i.ZERO)
	item["t"] = to
	if to < tiles.size():
		return false
	# In: ready to walk on, its ground's pictures drawn again, its animals out.
	var idx := _gen_index(r.position)
	_gen_done[idx] = 1
	_gen_busy.erase(idx)
	_gen_count += 1
	AssetPool.note("%s: ground chunk %d,%d in  (%d x %d tiles, %d of %d)" % [str(pdata.get("name", "")), idx / GEN_N, idx % GEN_N, GEN, GEN, _gen_count, GEN_N * GEN_N])
	_fauna_plans.append_array(res["fauna"])
	# (animals planned before the chunk's ledges were known: onto open ground)
	for f in _fauna_plans:
		if f["node"] == null and not f.has("ok") and r.has_point(_cell_at(f["pos"])):
			f["ok"] = true
			if not _ground_ok(f["pos"]):
				f["pos"] = _nearest_walkable(f["pos"])
	if ground_chunks:
		var corners := [_g2w * Vector2(r.position), _g2w * Vector2(r.end.x, r.position.y), _g2w * Vector2(r.end), _g2w * Vector2(r.position.x, r.end.y)]
		var box := Rect2(corners[0], Vector2.ZERO)
		for c in corners:
			box = box.expand(c)
		ground_chunks.refresh(box.grow(TTILES.LEVEL_PX * 21.0))
	if pilot and Rect2(r).grow(NAV_WIN).has_point(Vector2(_cell_at(pilot.position))):
		_nav_dirty = true
	if quest_giver == null and r.has_point(Vector2i(N / 2, N / 2)):
		_place_quest_giver()
	return true


## The ground's layer for a level (flat tiles, or the y-sorted blocks and ramps) - made when first needed.
func _tile_layer(l: int, ysort: bool) -> TileMapLayer:
	var key := l * 2 + (1 if ysort else 0)
	if not _tlayers.has(key):
		var layer := TileMapLayer.new()
		layer.tile_set = _tile_ts
		layer.y_sort_enabled = ysort
		layer.position = Vector2(0, -(l - _plot_lvl) * TTILES.LEVEL_PX)
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_tlayers[key] = layer
		tile_ground.add_child(layer)
		# (in order: higher levels drawn over lower, a level's blocks over its flat tiles)
		var keys := _tlayers.keys()
		keys.sort()
		for i in keys.size():
			tile_ground.move_child(_tlayers[keys[i]], i)
	return _tlayers[key]


## The whole planet at once (a planet without tiles, or with a layout saved
## in the editor): made on a worker, then built - as before the streaming.
func _build_whole() -> void:
	# The whole planet, on a worker thread: heights and terrain, the villages
	# (plots levelled), links to islands, the pictures of the ground and map.
	if _tiled:
		_tile_set_id = str(pdata["tiles"])
		_tile_pieces = TTILES.ground_pieces(_tile_set_id)
		# (its ground's pictures in first - waited for, the game going on - not
		# loaded on the spot: a dozen of them were a 3.5 s frame in a browser)
		ProcArt.prefetch(["tile_%s_" % _tile_set_id, "tile_"])   # (first; placeholders meanwhile)
		TTILES.prefetch(_tile_pieces)
		# (the set's cached scenery pictures decoded meanwhile, off the main thread)
		_decode_task = WorkerThreadPool.add_task(TTILES.predecode.bind(_tile_set_id), false, "Tile pictures")
	_gen_task = WorkerThreadPool.add_task(_generate_world, false, "Planet surface")
	while not WorkerThreadPool.is_task_completed(_gen_task) or (_decode_task >= 0 and not WorkerThreadPool.is_task_completed(_decode_task)):
		build_progress = maxf(build_progress, lerpf(0.05, 0.5, _gen_progress))
		build_stage = "Generating its terrain" if _gen_progress < 0.35 else ("Planning its villages and gates" if _gen_progress < 0.55 \
			else ("Linking its land: ramps and causeways" if _gen_progress < 0.85 else "Painting its ground and map"))
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(_gen_task)
	_gen_task = -1
	if _decode_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_decode_task)
		_decode_task = -1
	# (every other picture its buildings, scenery, creatures and people use -
	# loading while the planet was made - in before they're used)
	ProcArt.prefetch(["tile_", "creature_%s_" % str(pdata.get("tiles", "")), "npc_"])   # (placeholders till they're in)
	await _step(0.5, "ground")
	_build_ground()
	if _tiled:
		await _build_tile_ground()
	_build_map_texture()
	objects = Node2D.new()
	objects.y_sort_enabled = true
	add_child(objects)
	await _step(0.55, "buildings")
	await _place_everything()
	_stream_fauna()
	_place_quest_giver()
	await _build_prop_atlas()
	# What's around the landing pad: its scenery and the path-finding window.
	await _stream_initial()


## Back in the tree after waiting out of it (a surface built ahead, parked:
## main.gd) - what leaving undid, done again (_ready runs only once).
func _enter_tree() -> void:
	if not is_node_ready():
		return
	if _streamed and not get_tree().process_frame.is_connected(_pump_gen):
		get_tree().process_frame.connect(_pump_gen)
	if not RenderingServer.frame_pre_draw.is_connected(_apply_lifts):
		RenderingServer.frame_pre_draw.connect(_apply_lifts)
	if pdata:
		MinoanTiles.culture = culture()


func _exit_tree() -> void:
	if get_tree() and get_tree().process_frame.is_connected(_pump_gen):
		get_tree().process_frame.disconnect(_pump_gen)
	if MinoanTiles.culture == culture():
		MinoanTiles.culture = ""   # (the Library and the next world choose their own)
	if get_viewport():   # (far culling off: the viewport outlives this scene)
		get_viewport().canvas_cull_mask = get_viewport().canvas_cull_mask | FAR_LAYER
	if RenderingServer.frame_pre_draw.is_connected(_apply_lifts):
		RenderingServer.frame_pre_draw.disconnect(_apply_lifts)
	# (Waited for while letting the renderer run: the world's making reads
	# pictures back on its worker, which waits for the renderer the main
	# thread drives - blocked outright, quitting while a surface was being
	# built ahead never ended.)
	if _gen_task >= 0:
		_await_task(_gen_task)
		_gen_task = -1
	if _decode_task >= 0:
		_await_task(_decode_task)
		_decode_task = -1
	for id in _chunk_tasks.values():
		_await_task(id)
	_chunk_tasks.clear()
	if _nav_task >= 0:
		_await_task(_nav_task, _nav_stage != 3)
		_nav_task = -1


## A worker task (or group) waited for on the main thread without blocking the
## renderer it may need meanwhile (RenderingServer.force_sync while polling).
static func _await_task(id: int, group := false) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		if (WorkerThreadPool.is_group_task_completed(id) if group else WorkerThreadPool.is_task_completed(id)):
			break
		RenderingServer.force_sync()
		OS.delay_msec(1)
	if group:
		WorkerThreadPool.wait_for_group_task_completion(id)
	else:
		WorkerThreadPool.wait_for_task_completion(id)


## Makes the built surface the live game: shows it, its layers and camera,
## turns processing and input on.
func show_world() -> void:
	if not is_inside_tree():
		await tree_entered   # (the scene switch completes at the end of a frame)
	prebuilding = false
	background = false
	var fxn := get_node_or_null("FX")
	if fxn and not fxn.is_in_group("fx_layer"):
		fxn.add_to_group("fx_layer")
	if AttractMode.active and not has_meta("attract"):
		set_meta("attract", true)
		var a := AttractMode.new()   # (the title screen's attract mode: walking about, then off again)
		a.host = self
		add_child(a)
	NeonTheme.set_empire(Galaxy.owner_of(Galaxy.current_system))
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	for l in (_layers if not _layers.is_empty() else find_children("*", "CanvasLayer", true, false)):
		if is_instance_valid(l):
			l.visible = true
	if pilot:
		for c in pilot.get_children():
			if c is Camera2D:
				c.enabled = true
				if not c.is_inside_tree():
					await c.tree_entered
				c.make_current()
				c.reset_smoothing()
	# The ground in view rendered a few squares a frame while the landing's
	# fade is still black (all at once: a 200+ ms frame); it fades in once
	# world_settled().
	_unveil_frames = 0
	ground_force = false   # (it starts true: all at once - not now)
	_fauna_t = 0.1   # (the animals a moment later: not in the frame the world appears - a long one already)
	_fog_t = 0.05   # (the map revealed round you a moment later too)
	set_process(true)
	set_process_unhandled_input(true)
	set_process_input(true)
	SaveGame.travelling = false
	GameLog.post("Landed on %s. %s" % [pdata["name"], pdata["desc"]], "mission")
	get_tree().create_timer(1.5).timeout.connect(SaveGame.autosave.bind("landed on " + str(pdata["name"])))
	var env_note: String = Planets.environment(planet_id)["note"]
	if env_note != "":
		GameLog.post(env_note, "warning")   # (what the planet does to you on foot)


## The main quest's giver (QuestData.GIVER: Kilon Alios) stands by your
## landing pad on his planet (Amnissos, only there). Talking to him
## (talk_to_quest_giver) offers you the main quest, then tells you where it
## leads; while you haven't taken it, a QuestBulb glows over his head.
var quest_giver: Node2D
var _dialogue: Control


## Kilon Alios, by the landing pad of every world: the teller of New
## Hellas's story (on his home world, Amnissos, he offers the main quest).
func _place_quest_giver() -> void:
	var g: Dictionary = QuestData.GIVER
	var base: Vector2 = lander.position
	var spot := base + Vector2(-170, 70)
	for k in 24:
		var p := base + Vector2.from_angle(PI * 0.75 + k * 0.4) * (150.0 + k * 6.0)
		if walkable_at(p, 14.0):
			spot = p
			break
	var q := PROPS.QuestGiver.new()
	q.surface = self
	q.npc_name = str(g.get("name", "Kilon Alios"))
	q.role = str(g.get("role", "Wanderer"))
	q.position = spot
	q.offering = main_quest_stage() < 0 and _giver_home()   # (the quest's sign: over him on his home world)
	objects.add_child(q)
	quest_giver = q


## The main quest's stage in the space game you came down from (-1: not taken).
func main_quest_stage() -> int:
	return int(state.get("quest", {}).get("stage", -1))


## The story dialogue box (with portraits), made when first needed.
func dialogue_box() -> Control:
	if _dialogue == null:
		var layer := CanvasLayer.new()
		layer.layer = 30
		layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(layer)
		_dialogue = preload("res://scripts/dialogue.gd").new()
		_dialogue.process_mode = Node.PROCESS_MODE_ALWAYS
		layer.add_child(_dialogue)
	return _dialogue


## Talking to the quest giver: his greeting, then a conversation - a menu of
## questions (QuestData.GIVER topics: who he is, who you are, New Hellas,
## your mission, what you may become), the main quest, and Farewell. Each
## answer brings the menu back until you say farewell (or Esc).
func talk_to_quest_giver(g: Node) -> void:
	Scenarios.event("talked", {"planet": str(planet_id)})
	var greeting: Array = QuestData.GIVER.get("greeting", []) if _giver_home() else _giver_culture().get("greeting", QuestData.GIVER.get("greeting", []))
	dialogue_box().play(greeting, _giver_menu.bind(g))


## His home world (Amnissos), where the main quest is his to give.
func _giver_home() -> bool:
	return planet_id == str(QuestData.GIVER.get("planet", "thalassa"))


## What he says of the people holding this world (QuestData.GIVER "empires").
func _giver_culture() -> Dictionary:
	var emp: Dictionary = QuestData.GIVER.get("empires", {})
	return emp.get(culture(), emp.get("independent", {}))


## The questions you can put to him.
func _giver_menu(g: Node) -> void:
	var giver: Dictionary = QuestData.GIVER
	var options := []
	# Away from home: who he is, then this people's history and gods, then
	# the story of New Hellas. At home: his own questions, then the same.
	var topics: Array = giver.get("topics", []) if _giver_home() else giver.get("topics", []).slice(0, 1)
	topics = topics + _giver_culture().get("topics", []) + giver.get("hellas", [])
	for t in topics:
		var lines: Array = t.get("lines", [])
		options.append([str(t.get("ask", "?")), func(): dialogue_box().play(lines, _giver_menu.bind(g))])
	var taken := main_quest_stage() >= 0 or bool(state.get("quest", {}).get("finished", false))
	options.append([str(giver.get("quest_ask_later" if taken else "quest_ask", "The signal")), func(): _giver_quest(g)])
	options.append(["Farewell", func(): dialogue_box().play(giver.get("farewell", []))])
	UI.choice(self, str(giver.get("name", "Kilon Alios")), "What do you ask him?", options, true)


## The main quest's part of the conversation: the offer (then Accept / Not
## now) if you haven't taken it, else where it leads now (or his thanks).
func _giver_quest(g: Node) -> void:
	var giver: Dictionary = QuestData.GIVER
	var q: Dictionary = state.get("quest", {})
	var stage := main_quest_stage()
	var back := _giver_menu.bind(g)
	if bool(q.get("finished", false)):
		dialogue_box().play(giver["done"], back)
	elif stage >= 0:
		var lines: Array = giver["later"].duplicate(true)
		var st: Dictionary = QuestData.STAGES[clampi(stage, 0, QuestData.STAGES.size() - 1)]
		lines.append([giver["name"], "Where it leads now: [b]%s[/b]." % st["objective"]])
		dialogue_box().play(lines, back)
	else:
		dialogue_box().play(giver["offer"], func():
			UI.choice(self, str(giver["quest_title"]), str(giver["question"]), [
				["Not now", func(): dialogue_box().play(giver["declined"], back)],
				["Accept", func(): accept_main_quest(g)]]))


## You took the main quest from its giver: it starts (at its first stage)
## when you're back in space; its opening plays here, after his reply.
func accept_main_quest(g: Node = null) -> void:
	if main_quest_stage() >= 0:
		return
	state["quest"] = {"stage": 0, "finished": false, "lore": state.get("quest", {}).get("lore", [])}
	if g:
		g.offering = false
	var first: Dictionary = QuestData.STAGES[0]
	GameLog.post("Main quest accepted: %s" % QuestData.GIVER["quest_title"], "quest")
	GameLog.post(QuestData.CHAPTERS[first["chapter"]], "quest")
	GameLog.post("New objective: " + first["objective"], "quest")
	var lines: Array = QuestData.GIVER["accepted"].duplicate(true)
	lines.append_array(first.get("dialogue", []))
	dialogue_box().play(lines)


## Built hidden in the space scene during the landing animation (see main.gd).
var prebuilding := false
## 0..1 while building.
var build_progress := 0.0


## The surface is ready (built in steps).
signal built
var is_built := false
## What the build is doing (the loading bar above the event log).
var build_stage := ""
## Built ahead from space (main.gd _prebuild): the planet and the game's state
## given here, not read from SaveGame (you aren't landed yet); `background`:
## a gentler share of each frame meanwhile (you're flying).
var planet_override := ""
var state_override: Dictionary = {}
var background := false
## (built ahead, then not wanted - you flew off, jumped away: taken apart once built)
var discard := false
var _layers: Array = []   # (its CanvasLayers, listed when built)
var _loading := false
var _slice_t := 0


## Loading: shows progress and lets a frame through.
const STAGE_TEXT := {"terrain": "Generating its terrain", "ground": "Laying its ground tiles",
	"buildings": "Raising its buildings and scenery", "hud": "Finishing"}

func _step(progress: float, _stage: String) -> void:
	build_progress = maxf(build_progress, progress)
	build_stage = STAGE_TEXT.get(_stage, _stage)
	await get_tree().process_frame
	if discard:
		# (built ahead, no longer wanted: stopped here - between stages nothing's
		# half done and no worker task runs - and taken apart a few ms a frame;
		# this build never goes on)
		UI.dismantle(self)
		await _never
	_slice_t = Time.get_ticks_usec()
	if background:
		_slice_us = BgWork.take()


signal _never


## Inside long loops while loading: let a frame through every few ms (the
## landing animation runs meanwhile).
func _yield_due() -> bool:
	return _loading and Time.get_ticks_usec() - _slice_t > (_slice_us if background else (3000 if prebuilding else 6000))   # (landing: the animation at full frame rate; built ahead while you fly: BgWork's paced share)


## (built ahead: this slice's share of the main thread - BgWork.take(), paced by time)
var _slice_us := 0


func _breathe(progress := -1.0, _stage := "") -> void:
	if progress >= 0.0:
		build_progress = maxf(build_progress, progress)
	await get_tree().process_frame
	_slice_t = Time.get_ticks_usec()
	if background:
		_slice_us = BgWork.take()


# --- Terrain -----------------------------------------------------------------------

## Raises all land a little: water and crevasses are the occasional lake or
## crack to walk around, not a maze (also applied to saved layouts).
const LAND_BIAS := 0.3


## The whole planet (worker thread; touches no nodes): terrain, the villages'
## plans with their plots levelled, causeways to islands, the height map and
## map pictures as bytes, and the scenery looks for the atlas.
var _gen_progress := 0.0
var _gen_task := -1
var _ground_data := PackedFloat32Array()   # (height, rock) per pixel for the ground texture
var _ground_mesh: Array = []                # [vertices, indices] (SurfaceTerrain.ground_mesh)
var _window_mesh: Array = []                # the fine mesh near the camera (SurfaceTerrain.window_mesh)
## The ground near the camera is a finer mesh (FINE_SUB x FINE_SUB quads a
## tile, FINE_W tiles square, following the camera): crisp cliffs; the whole
## map's coarse mesh shows beyond it.
const FINE_W := 100
const FINE_SUB := 4
var _fine_mat: ShaderMaterial
var _coarse_mat: ShaderMaterial
var _win_origin := Vector2i(-99999, 0)
## The water's height (the top of the highest unwalkable band; -1: none) -
## the level it lies flat at (SurfaceTerrain.elevation).
var _water_top := -1.0
var _map_bytes := PackedByteArray()
var _atlas_looks: Array = []

## pdata's thresholds and walkable flags as packed arrays (hot paths, threads).
var _th := PackedFloat32Array()
var _walk_t := PackedByteArray()

func _generate_world() -> void:
	_th = PackedFloat32Array(pdata["thresholds"])
	for t in pdata["terrain"]:
		_walk_t.append(1 if t[2] else 0)
	_generate_terrain()
	_site_h = _site_height()
	_water_top = -1.0
	for t in pdata["terrain"].size():
		if pdata["terrain"][t][2]:
			_water_top = pdata["thresholds"][t - 1] if t > 0 else -1.0
			break
	_gen_progress = 0.35
	# (a layout saved on a bigger planet than this - the 880-tile one - no longer fits: a fresh planet)
	var lh: Array = _layout.get("heights", [])
	if lh.size() > N * N:
		_layout = {}
	_apply_layout_heights()
	if _layout.is_empty():
		_plan_world()
	_plan_gates()
	_gen_progress = 0.55
	# The ledges' elevation; their cliffs are solid; then everything is linked
	# (causeways, and ramps cut through cliffs: their elevation again).
	if _tiled:
		if str(pdata.get("water", "")) == "islands":
			# Bridges between the platforms: each pass links the patches within
			# MAX_CAUSEWAY of the land reached so far, which grows with them.
			var th2: Array = pdata["thresholds"]
			for pass_ in 12:
				if not _connect_islands():
					break
				for k in N * N:   # (the carving sets heights only: the bridges' cells are land now)
					var t2 := 0
					while t2 < th2.size() and _height[k] > th2[t2]:
						t2 += 1
					_terrain[k] = t2
		_plan_tiles()
	else:
		_crag = _rock.duplicate()
		_blur_ramp()
		_compute_elev()
		_mark_cliffs()
		_gen_progress = 0.65
		if _connect_islands():
			_blur_ramp()
			_compute_elev()
			_mark_cliffs()   # (the ramps cut through them)
		_fill_unreached()
	_plan_fauna()
	_gen_progress = 0.85
	var th: Array = pdata["thresholds"]
	_ground_data.resize(N * N * 4)
	_map_bytes.resize(N * N * 3)
	var cols: Array = pdata["terrain"].map(func(t): return t[1])
	for i in N:
		for j in N:
			var k := i * N + j
			var h := _height[k]
			var t := 0
			while t < th.size() and h > th[t]:
				t += 1
			_terrain[k] = t
			# (images are row-major: pixel (x = i, y = j))
			var px := j * N + i
			_ground_data[px * 4] = (h + 1.0) * 0.5
			_ground_data[px * 4 + 1] = _rock[k] / 255.0
			_ground_data[px * 4 + 2] = _ramp[k]
			_ground_data[px * 4 + 3] = _crag[k] / 255.0
			var c: Color = cols[t]
			_map_bytes[px * 3] = c.r8
			_map_bytes[px * 3 + 1] = c.g8
			_map_bytes[px * 3 + 2] = c.b8
	_style_map_bytes()
	_atlas_looks = _sample_looks()
	if not _tiled:
		_ground_mesh = TERRAIN.ground_mesh(N, _g2w)
		_window_mesh = TERRAIN.window_mesh(FINE_W, FINE_SUB)
	else:
		_tile_ts = TTILES.tile_set(_tile_pieces)   # (its pieces' images made here, off the main thread)
		_tile_cells()
	_gen_progress = 1.0


## The map's look (planet map and minimap), in the GUI's amber console style:
## near-black sea (a breath of blue) with a faint grid, dark umber land tinted
## by its terrain, hillshaded - slopes facing the light lit amber, the others
## in shadow - and glowing pale-amber coastlines.
const MAP_SEA := Color(0.014, 0.02, 0.032)
const MAP_SHALLOW := Color(0.03, 0.045, 0.062)
const MAP_LAND := Color(0.085, 0.06, 0.032)
const MAP_LIT := Color(1.0, 0.56, 0.16)
const MAP_COAST := Color(1.0, 0.76, 0.42)
const MAP_GRID := 44                 # tiles between grid lines on the sea
const MAP_ELEV_HIGH := Color(0.88, 0.92, 0.8)   # tiled ground: the highest level's tint (the map's elevation)
var _lvl_top := -1


func _is_water(t: int) -> bool:
	return _walk_t[t] == 0


const _NB: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]
var _tcol: Array = []                # terrain colours (pdata), for the map


## The stylised colour of grid cell (i, j) (heights and terrain types known).
func _map_color(i: int, j: int) -> Color:
	var k := i * N + j
	var t: int = _terrain[k]
	var h := _height[k]
	var water := _is_water(t)
	# Next to the other kind of cell (1 or 2 away): the coast.
	var coast := 0
	for d in _NB:
		var q := Vector2i(i, j) + d
		if q.x < 0 or q.y < 0 or q.x >= N or q.y >= N:
			continue
		if (_walk_t[_terrain[q.x * N + q.y]] == 0) != water:
			coast = 2 if absi(d.x) + absi(d.y) == 1 else maxi(coast, 1)
			if coast == 2:
				break
	var c: Color
	if water:
		c = MAP_SEA.lerp(MAP_SHALLOW, clampf(float(t) / maxf(1.0, _first_land() - 1.0), 0.0, 1.0))
		if i % MAP_GRID == 0 or j % MAP_GRID == 0:
			c = c.lerp(Color(0.1, 0.35, 0.45), 0.35)
		if coast > 0:
			c = c.lerp(Color(0.1, 0.5, 0.65), 0.55 if coast == 2 else 0.25)
		return c
	if _tcol.is_empty():
		_tcol = pdata["terrain"].map(func(x): return x[1])
	var tc: Color = _tcol[t]
	c = MAP_LAND.lerp(tc, 0.42)
	if _tiled and _lvl.size() == N * N:
		# Tiled ground's levels: the higher, the lighter (low ground dark), each
		# level's edge outlined where the ground drops, ramps marked pale.
		if _lvl_top < 0:
			for q in N * N:
				_lvl_top = maxi(_lvl_top, _lvl[q])
		var lv := int(_lvl[k])
		c = c.darkened(0.35).lerp(MAP_ELEV_HIGH, 0.75 * float(lv) / maxf(1.0, float(_lvl_top)))
		if _rampd[k] != 0:
			c = c.lerp(Color(0.95, 0.9, 0.7), 0.6)
		else:
			for q in [k - N if i > 0 else -1, k + N if i < N - 1 else -1, k - 1 if j > 0 else -1, k + 1 if j < N - 1 else -1]:
				if q >= 0 and _walk_t[_terrain[q]] == 1 and int(_lvl[q]) < lv:
					c = c.darkened(0.5)   # (a cliff edge: the ground drops here)
					break
	else:
		c = c.lightened(clampf(h, 0.0, 1.0) * 0.12)
	# Hillshade from the broad slope (12 cells either side - not every bump):
	# the light comes from the top of the map; the ridges facing it glow orange.
	var hx := _height[mini(i + 12, N - 1) * N + j] - _height[maxi(i - 12, 0) * N + j]
	var hy := _height[i * N + mini(j + 12, N - 1)] - _height[i * N + maxi(j - 12, 0)]
	var sh := clampf(-(hx + hy) * 1.6, -1.0, 1.0)
	if sh > 0.45:
		c = c.lerp(MAP_LIT, (sh - 0.45) * 0.8)
	elif sh < 0.0:
		c = c.darkened(-sh * 0.35)
	if _solid(k) >= 128:   # crags and cliffs: pale rock
		c = c.lerp(Color(0.62, 0.6, 0.55), 0.6)
	elif _rock[k] >= 60:
		c = c.lerp(Color(0.4, 0.4, 0.37), 0.25)
	if coast == 2:
		c = MAP_COAST
	elif coast == 1:
		c = c.lerp(MAP_COAST, 0.3)
	return c


var _first_land_i := -1
func _first_land() -> float:
	if _first_land_i < 0:
		_first_land_i = 0
		while _first_land_i < pdata["terrain"].size() and _is_water(_first_land_i):
			_first_land_i += 1
	return float(_first_land_i)


## The whole picture in the stylised look (on the worker thread).
func _style_map_bytes() -> void:
	for i in N:
		for j in N:
			var c := _map_color(i, j)
			var px := (j * N + i) * 3
			_map_bytes[px] = c.r8
			_map_bytes[px + 1] = c.g8
			_map_bytes[px + 2] = c.b8


## Repaints part of the picture (terrain changed there) - with a margin,
## since coasts and shading look at the neighbours.
func _repaint_map(area: Rect2i) -> void:
	var r := area.grow(2).intersection(Rect2i(0, 0, N, N))
	for i in range(r.position.x, r.end.x):
		for j in range(r.position.y, r.end.y):
			_map_img.set_pixel(i, j, _map_color(i, j))
	map_tex.update(_map_img)


## The overview picture of the terrain (minimap and planet map).
var map_tex: ImageTexture
var _map_img: Image

func _build_map_texture() -> void:
	_map_img = Image.create_from_data(N, N, false, Image.FORMAT_RGB8, _map_bytes)
	map_tex = ImageTexture.create_from_image(_map_img)
	_map_bytes = PackedByteArray()
	_setup_fog()


## Fog of war on the minimap and the planet map: what you've seen of this
## planet (FogOfWar in grid coordinates, one cell per FOG_CELL tiles),
## revealed FOG_REVEAL tiles round you as you walk, kept in the state
## ("planets" -> "explored") so it's remembered.
const FOG_CELL := 4
const FOG_REVEAL := 44.0
var fog: FogOfWar
var _fog_t := 0.0


func _setup_fog() -> void:
	fog = FogOfWar.new(N / FOG_CELL, N / FOG_CELL, Vector2.ZERO, float(FOG_CELL))
	fog.smooth = 1   # (the maps draw it filtered - soft edges without resizing it 4x on every update: 1.3 ms)
	fog.load_from(str(state["planets"][planet_id].get("explored", "")))


## Where you are on the fog's grid.
func reveal_around(world: Vector2) -> bool:
	return fog != null and fog.reveal(_world_to_grid * world + Vector2(0.5, 0.5), FOG_REVEAL)


## Seen on the maps (explored)?
func explored_at(world: Vector2) -> bool:
	return fog == null or fog.explored(_world_to_grid * world + Vector2(0.5, 0.5))


func _store_fog() -> void:
	if fog != null:
		state["planets"][planet_id]["explored"] = fog.save()


# --- Scenery chunks ---------------------------------------------------------------------

var _chunks := {}                   # chunk -> true: its scenery is (being) placed
var _chunk_nodes := {}              # chunk -> its scenery nodes
var _chunk_data := {}               # chunk -> its flat scenery (PropData)
var _chunk_holders := {}            # chunk -> the node holding its scenery nodes
var _chunk_tasks := {}              # chunk -> worker task growing its scenery
var _chunk_results := {}            # chunk -> grown scenery, waiting to be placed
var _chunk_lock := Mutex.new()
var _place_queue: Array = []        # [chunk, scenery, next index]

func _chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK), floori(float(cell.y) / CHUNK))


## Keeps the scenery around you: grows the chunks within LOAD_R on worker
## threads (nearest first), places what's grown within `budget_us` of this
## frame, and frees chunks beyond UNLOAD_R.
func _stream_chunks(budget_us: int) -> void:
	var pc := _chunk_of(_cell_at(pilot.position))
	var maxc := (N - 1) / CHUNK
	var want: Array = []
	for dx in range(-LOAD_R, LOAD_R + 1):
		for dy in range(-LOAD_R, LOAD_R + 1):
			var key := pc + Vector2i(dx, dy)
			if key.x >= 0 and key.y >= 0 and key.x <= maxc and key.y <= maxc \
					and not _chunks.has(key) and not _chunk_tasks.has(key) and not _queued(key) \
					and gen_ready(key * CHUNK + Vector2i(CHUNK / 2, CHUNK / 2)):
				want.append(key)
	want.sort_custom(func(a, b): return (a - pc).length_squared() < (b - pc).length_squared())
	for key in want:
		if _chunk_tasks.size() >= (1 if background else BgWork.threads()):
			break   # (a few at a time: background work may take a quarter of the machine)
		_chunk_tasks[key] = WorkerThreadPool.add_task(func() -> void:
			var d := _chunk_flora(key)
			_chunk_lock.lock()
			_chunk_results[key] = d
			_chunk_lock.unlock(), false, "Surface scenery")
	for key in _chunk_tasks.keys():
		if WorkerThreadPool.is_task_completed(_chunk_tasks[key]):
			WorkerThreadPool.wait_for_task_completion(_chunk_tasks[key])
			_chunk_tasks.erase(key)
			_chunk_lock.lock()
			_place_queue.append([key, _chunk_results[key], 0])
			_chunk_results.erase(key)
			_chunk_lock.unlock()
	_place_queue.sort_custom(func(a, b): return (a[0] - pc).length_squared() < (b[0] - pc).length_squared())
	var t0 := Time.get_ticks_usec()
	while not _place_queue.is_empty() and Time.get_ticks_usec() - t0 < budget_us:
		var q: Array = _place_queue[0]
		var key: Vector2i = q[0]
		if _cheb(key, pc) > UNLOAD_R:
			_place_queue.pop_front()
			continue
		_chunks[key] = true
		var data: Array = q[1]
		var end := mini(int(q[2]) + 48, data.size())
		for k in range(q[2], end):
			var d: Array = data[k]
			_spawn_prop(d[0], d[1], d[2], d[3], d[4], true)
		q[2] = end
		if end >= data.size():
			_place_queue.pop_front()
			if _decor_batches.has(key):
				_decor_batches[key].queue_redraw()
	var freed := 0
	for key in _chunks.keys():
		if _cheb(key, pc) > UNLOAD_R and freed < 2:   # (a couple a frame)
			_unload_chunk(key)
			freed += 1


func _queued(key: Vector2i) -> bool:
	for q in _place_queue:
		if q[0] == key:
			return true
	return false


func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Frees a chunk's scenery (it grows back the same when you return).
func _unload_chunk(key: Vector2i) -> void:
	_chunks.erase(key)
	var batch: Node2D = _decor_batches.get(key)
	if batch:
		batch.free()
		_decor_batches.erase(key)
	for p in _chunk_nodes.get(key, []):
		_props.erase(p)
		_tall_props.erase(p)
	_chunk_nodes.erase(key)
	var holder: Node2D = _chunk_holders.get(key)
	if holder:
		holder.free()
		_chunk_holders.erase(key)
	var b0 := key * CHUNK / 4
	for bx in CHUNK / 4:
		for by in CHUNK / 4:
			_prop_buckets.erase(b0 + Vector2i(bx, by))
	for d in _chunk_data.get(key, []):
		_props.erase(d)
	_chunk_data.erase(key)
	_faded = _faded.filter(func(p): return is_instance_valid(p))


## While loading: the scenery around the pad, all placed, and the path grid.
func _stream_initial() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < (120000 if background else 20000):
		_stream_chunks(maxi(200, _slice_us) if background else 6000)   # (built ahead: the paced share)
		if _chunk_tasks.is_empty() and _place_queue.is_empty():
			break
		await _breathe(lerpf(0.6, 0.85, minf(1.0, _chunks.size() / 25.0)), "Planting trees and scenery")
	if background:
		_nav_dirty = true   # (built ahead: no paths needed till you land - made then, in its first frames)
	else:
		await _build_nav()


## Every scenery look the planet can grow (for the prop atlas): the flora of
## each walkable terrain kind, rolled many times.
func _sample_looks() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pdata["seed"]) * 7 + 1
	var leaf: Color = pdata["prop_color"]
	var seen := {}
	var out := []
	for t in pdata["terrain"]:
		if not t[2]:
			continue
		for k in 600:
			for spec in _flora_for(t[3], leaf, rng):
				var v := rng.randi()
				var key := PROPS.atlas_key(spec[0], spec[1], v)
				if not seen.has(key):
					seen[key] = true
					out.append([spec[0], spec[1], v])
	return out


## Heights and crags (SurfaceTerrain: Greek-style relief, one coast / lake /
## river, limestone crags), then the terrain bands from the heights.
func _generate_terrain() -> void:
	var g: Dictionary = TERRAIN.generate(N, pdata, int(pdata["seed"]))
	_height = g["height"]
	_rock = g["rock"]
	_ramp = g["ramp"]
	var thresholds: Array = pdata["thresholds"]
	_terrain.resize(N * N)
	for k in N * N:
		var t := 0
		while t < thresholds.size() and _height[k] > thresholds[t]:
			t += 1
		_terrain[k] = t


## (worker thread) No crags within `radius` (+2 tiles) of a cell.
func _clear_rock(cell: Vector2i, radius: float) -> void:
	var r := ceili(radius) + 2
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var q := cell + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < N and q.y < N and Vector2(dx, dy).length() <= r + 0.5:
				_rock[q.x * N + q.y] = 0
				if _crag.size() == N * N:
					_crag[q.x * N + q.y] = 0
			_set_ramp(cell, r + 3.0)


## (worker thread) Ledges meet in slopes (not cliffs) within `radius` of a cell
## (easing out over 3 more tiles).
func _set_ramp(cell: Vector2i, radius: float) -> void:
	if _ramp.size() != N * N:
		return
	var r := ceili(radius + 3.0)
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var q := cell + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < N and q.y < N:
				var k := 1.0 - smoothstep(radius, radius + 3.0, Vector2(dx, dy).length())
				_ramp[q.x * N + q.y] = maxf(_ramp[q.x * N + q.y], k)


## Open ground kept free of scenery (and crags).
func _add_clear_spot(cell: Vector2i, radius: float) -> void:
	_clear_spots.append([cell, radius])
	_clear_rock(cell, radius)


## A crag stands on this cell (its middle: the filtered value is the cell's own).
func _rock_cell(c: Vector2i) -> bool:
	return _rock.size() == N * N and _solid(c.x * N + c.y) >= 90   # (just under the solid line: tiles a crag's edge cuts aren't open ground)


func terrain_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= N or cell.y >= N:
		return -1
	return _terrain[cell.x * N + cell.y]


func terrain_color(cell: Vector2i) -> Color:
	var t := terrain_at(cell)
	return pdata["terrain"][t][1] if t >= 0 else Color.BLACK


func walkable_cell(cell: Vector2i) -> bool:
	var t := terrain_at(cell)
	return t >= 0 and pdata["terrain"][t][2] and not _rock_cell(cell)


## Walkable where the ground *looks* walkable: uses the same smoothly
## interpolated height as the ground shader, so coastlines match exactly.
func walkable_at(world: Vector2, wall_clear := 6.0) -> bool:
	if not _ground_ok(world):
		return false
	if not _bgrid_ok:
		_index_buildings()
	var near: Array = _bgrid.get(Vector2i((world / BGRID).floor()), _NONE)
	if near.is_empty():
		return true
	if wall_clear + 9.0 > FINE_REACH:
		return _clear_of_buildings(world, wall_clear, near)
	for b in near:
		if b.bounds.has_point(world) and not _clear_in(b, world, wall_clear):
			return false
	return true


## Within a building: only its walls, columns and furniture near the point
## (a FINE-px grid of them, each in the squares it reaches FINE_REACH px
## into) - the same tests as _clear_of_buildings, a dozen shapes instead of
## a few hundred. Rebuilt when its walls / columns / furniture change.
const FINE := 48.0
const FINE_REACH := 32.0
var _bfine := {}   # building -> [counts, {square: [[kind, data]...]}]

func _clear_in(b, world: Vector2, wall_clear: float) -> bool:
	return _clear_in_grid(_fine_of(b), world, wall_clear)


## A building's fine grid, (re)made if its walls / columns / furniture changed (main thread).
func _fine_of(b) -> Dictionary:
	var counts := [b.segments.size(), b.pillars.size(), b.blocks.size(), b.upper != null]
	var e: Array = _bfine.get(b, _NONE)
	if e.is_empty() or e[0] != counts:
		e = [counts, _fine_grid(b)]
		_bfine[b] = e
	return e[1]


## _clear_in against a given fine grid (read only: worker threads use it too).
func _clear_in_grid(grid: Dictionary, world: Vector2, wall_clear: float) -> bool:
	var c2 := wall_clear * wall_clear
	for sh in grid.get(Vector2i((world / FINE).floor()), _NONE):
		match sh[0]:
			0:   # a wall
				if world.distance_squared_to(Geometry2D.get_closest_point_to_segment(world, sh[1], sh[2])) < c2:
					return false
			1:   # a column
				if world.distance_squared_to(sh[1]) < (wall_clear + 9.0) * (wall_clear + 9.0):
					return false
			_:   # furniture, the staircase
				var poly: PackedVector2Array = sh[1]
				if Geometry2D.is_point_in_polygon(world, poly):
					return false
				for k in poly.size():
					if world.distance_squared_to(Geometry2D.get_closest_point_to_segment(world, poly[k], poly[(k + 1) % poly.size()])) < c2:
						return false
	return true


func _fine_grid(b) -> Dictionary:
	var g := {}
	var put := func(sh: Array, r: Rect2) -> void:
		r = r.grow(FINE_REACH)
		var lo := Vector2i((r.position / FINE).floor())
		var hi := Vector2i((r.end / FINE).floor())
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				var k := Vector2i(x, y)
				if not g.has(k):
					g[k] = []
				g[k].append(sh)
	for seg in b.segments:
		put.call([0, seg[0], seg[1]], Rect2(seg[0], Vector2.ZERO).expand(seg[1]))
	for pp in b.pillars:
		put.call([1, pp], Rect2(pp, Vector2.ZERO))
	var polys: Array = b.blocks.duplicate()
	if b.upper != null:
		polys.append(b.upper.solid)
	for poly in polys:
		var r := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			r = r.expand(q)
		put.call([2, poly], r)
	return g


## The buildings by BGRID-px squares of the ground (each in every square its
## bounds touch): walkable_at - hundreds of calls a frame, the animals
## walking - only looks at the ones near the point. Rebuilt when a building
## comes or goes (_bgrid_ok).
const BGRID := 512.0
const _NONE: Array = []
var _bgrid := {}
var _bgrid_ok := false

func _index_buildings() -> void:
	_bgrid.clear()
	_bfine.clear()
	for b in buildings:
		var r: Rect2 = b.bounds
		var lo := Vector2i((r.position / BGRID).floor())
		var hi := Vector2i((r.end / BGRID).floor())
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				var k := Vector2i(x, y)
				if not _bgrid.has(k):
					_bgrid[k] = []
				_bgrid[k].append(b)
	_bgrid_ok = true


## For worker threads: the buildings `bs` indexed as walkable_at has them -
## by BGRID squares, each with its fine grid - made on the main thread, then
## only read (the path grid's build tested every wall of every building for
## each of its points: on four cores it starved the game of time).
func _snapshot_index(bs: Array) -> Dictionary:
	var cells := {}
	var fine := {}
	for b in bs:
		fine[b] = _fine_of(b)
		var r: Rect2 = b.bounds
		var lo := Vector2i((r.position / BGRID).floor())
		var hi := Vector2i((r.end / BGRID).floor())
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				var k := Vector2i(x, y)
				if not cells.has(k):
					cells[k] = []
				cells[k].append(b)
	return {"cells": cells, "fine": fine}


## walkable_at from a _snapshot_index (worker threads).
func _walkable_snap(world: Vector2, wall_clear: float, idx: Dictionary) -> bool:
	if not _ground_ok(world):
		return false
	var near: Array = idx["cells"].get(Vector2i((world / BGRID).floor()), _NONE)
	if wall_clear + 9.0 > FINE_REACH:
		return _clear_of_buildings(world, wall_clear, near)
	for b in near:
		if b.bounds.has_point(world) and not _clear_in_grid(idx["fine"][b], world, wall_clear):
			return false
	return true


## walkable_at against the buildings in `bs` (every wall of each: slow - see _walkable_snap).
func _walkable_in(world: Vector2, wall_clear: float, bs: Array) -> bool:
	if not _ground_ok(world):
		return false
	return _clear_of_buildings(world, wall_clear, bs)


func _clear_of_buildings(world: Vector2, wall_clear: float, bs: Array) -> bool:
	# Building walls block (doorways are gaps in them); so do columns.
	for b in bs:
		if not b.bounds.has_point(world):
			continue
		for seg in b.segments:
			if world.distance_squared_to(Geometry2D.get_closest_point_to_segment(world, seg[0], seg[1])) < wall_clear * wall_clear:
				return false
		for pp in b.pillars:
			if world.distance_squared_to(pp) < (wall_clear + 9.0) * (wall_clear + 9.0):
				return false
		for poly in b.blocks:   # furniture
			if Geometry2D.is_point_in_polygon(world, poly):
				return false
			for k in poly.size():
				if world.distance_squared_to(Geometry2D.get_closest_point_to_segment(world, poly[k], poly[(k + 1) % poly.size()])) < wall_clear * wall_clear:
					return false
		if b.upper != null:   # the staircase
			var sol: PackedVector2Array = b.upper.solid
			if Geometry2D.is_point_in_polygon(world, sol):
				return false
			for k in sol.size():
				if world.distance_squared_to(Geometry2D.get_closest_point_to_segment(world, sol[k], sol[(k + 1) % sol.size()])) < wall_clear * wall_clear:
					return false
	return true


## The ground itself is walkable here (not sea / crevasse / off the map).
func _ground_ok(world: Vector2) -> bool:
	var g := _world_to_grid * world
	if g.x < -0.5 or g.y < -0.5 or g.x > N - 0.5 or g.y > N - 0.5:
		return false
	if _tiled:
		return _tile_ground_ok(g)
	var h := _height_interp(g)
	var t := 0
	while t < _th.size() and h > _th[t]:
		t += 1
	if _walk_t[t] == 0:
		return false
	# Crags: from the foot of their cliffs in, exactly as the ground shader
	# draws them (the same filtered rock); the cliffs between ledges, where
	# the ground climbs as steeply as the shader draws a wall.
	if _rock.size() == N * N and TERRAIN.rock_interp(_rock, N, g) >= TERRAIN.ROCK_SOLID:
		return false
	if _cliff.size() == N * N and _on_cliff(g):
		return false
	return true


## How high the ground stands at a ground-plane point (screen px up) - the
## mesh's elevation there: what stands on it is drawn that much higher.
func lift_at(world: Vector2) -> float:
	if _tiled:
		return _tile_lift(_world_to_grid * world)
	if _elev.size() != N * N:
		return 0.0
	var g := _world_to_grid * world
	var x0 := clampi(floori(g.x), 0, N - 1)
	var y0 := clampi(floori(g.y), 0, N - 1)
	var x1 := mini(x0 + 1, N - 1)
	var y1 := mini(y0 + 1, N - 1)
	var fx := clampf(g.x - x0, 0.0, 1.0)
	var fy := clampf(g.y - y0, 0.0, 1.0)
	# (the filtered height, ramp and crags - as the shader samples them - then the ledges)
	var ramp := lerpf(lerpf(_ramp[x0 * N + y0], _ramp[x1 * N + y0], fx), lerpf(_ramp[x0 * N + y1], _ramp[x1 * N + y1], fx), fy)
	return TERRAIN.elevation(_height_interp(g), ramp, TERRAIN.rock_interp(_crag, N, g), g, N, _water_top, _site_h)


## The fine ground window follows the camera (in whole tiles).
func _move_window() -> void:
	if _fine_mat == null or not is_instance_valid(pilot):
		return
	var g := _world_to_grid * pilot.position
	var o := Vector2i(floori(g.x) - FINE_W / 2, floori(g.y) - FINE_W / 2)
	if o == _win_origin:
		return
	_win_origin = o
	_fine_mat.set_shader_parameter("win_origin", Vector2(o))
	_coarse_mat.set_shader_parameter("win_origin", Vector2(o))


## (worker thread / editor) The elevation of the tiles in `area` (SurfaceTerrain.elevation).
func _compute_elev(area := Rect2i(0, 0, N, N)) -> void:
	if _elev.size() != N * N:
		_elev.resize(N * N)
	var r := area.intersection(Rect2i(0, 0, N, N))
	for i in range(r.position.x, r.end.x):
		for j in range(r.position.y, r.end.y):
			var k := i * N + j
			_elev[k] = TERRAIN.elevation(_height[k], _ramp[k], _crag[k] / 255.0, Vector2(i, j), N, _water_top, _site_h)


## (worker thread) The tiles a cliff runs through (_cliff): a ledge's drop
## (SurfaceTerrain.terrace: the band of x below each whole ledge) crossing the
## tile's span (half way to each neighbour) where it climbs CLIFF_PX a tile
## or more. Walkability tests the exact slope there (_ground_ok); the rest
## of the game treats these tiles as solid (_solid).
func _mark_cliffs() -> void:
	_cliff.resize(N * N)
	_cliff.fill(0)
	var cw := TERRAIN.CLIFF_W
	var peak := 0.15 + 0.85 * 1.5 / cw          # the drop's steepest (per ledge of x)
	var xs := PackedFloat32Array()
	xs.resize(N * N)
	for k in N * N:
		xs[k] = (maxf(_height[k], _water_top) - _site_h) / TERRAIN.TERRACE
	for i in range(1, N - 1):
		for j in range(1, N - 1):
			var k := i * N + j
			var x := xs[k]
			var xw := xs[k - N]
			var xe := xs[k + N]
			var xn := xs[k - 1]
			var xs_ := xs[k + 1]
			var lo := minf(x, minf(minf(xw, xe), minf(xn, xs_)) * 0.5 + x * 0.5)
			var hi := maxf(x, maxf(maxf(xw, xe), maxf(xn, xs_)) * 0.5 + x * 0.5)
			var r := minf(_ramp[k], minf(minf(_ramp[k - N], _ramp[k + N]), minf(_ramp[k - 1], _ramp[k + 1])))
			if r >= 0.5:
				continue   # (ramps are ways up, never walls)
			var grad := maxf(absf(xe - xw), absf(xs_ - xn)) * 0.5
			var drop := hi >= ceilf(lo) - cw   # (a ledge's drop in this tile's span)
			var e := _elev[k]
			var jump := maxf(maxf(absf(_elev[k - N] - e), absf(_elev[k + N] - e)), maxf(absf(_elev[k - 1] - e), absf(_elev[k + 1] - e)))
			if TERRAIN.STEP * grad * ((1.0 - r) * (peak if drop else 0.15) + r) >= TERRAIN.CLIFF_PX * 0.9 or jump >= TERRAIN.CLIFF_PX * 0.9:
				_cliff[k] = 255


## (worker thread) Ramps fade in over a few tiles (a box blur, 3 tiles each
## way, twice): a ramp's edge is no step of its own.
func _blur_ramp() -> void:
	var tmp := PackedFloat32Array()
	tmp.resize(N * N)
	for pass_ in 2:
		for i in N:   # along j
			var acc := 0.0
			for j in range(-3, N + 3):
				if j + 3 < N:
					acc += _ramp[i * N + j + 3]
				if j - 4 >= 0:
					acc -= _ramp[i * N + j - 4]
				if j >= 0 and j < N:
					tmp[i * N + j] = acc / 7.0
		for j in N:   # along i
			var acc := 0.0
			for i in range(-3, N + 3):
				if i + 3 < N:
					acc += tmp[(i + 3) * N + j]
				if i - 4 >= 0:
					acc -= tmp[(i - 4) * N + j]
				if i >= 0 and i < N:
					_ramp[i * N + j] = acc / 7.0


## Solid ground at a tile (0..255): crags, nooks filled in, cliffs.
func _solid(k: int) -> int:
	return maxi(_rock[k], _cliff[k]) if _cliff.size() == N * N else _rock[k]


## A cliff here: the ground climbs CLIFF_PX a tile or more - exactly as the
## ground shader draws its walls (the same elevation, the same slope).
func _on_cliff(g: Vector2) -> bool:
	var x0 := clampi(floori(g.x), 0, N - 1)
	var y0 := clampi(floori(g.y), 0, N - 1)
	var x1 := mini(x0 + 1, N - 1)
	var y1 := mini(y0 + 1, N - 1)
	if _cliff[x0 * N + y0] == 0 and _cliff[x1 * N + y0] == 0 and _cliff[x0 * N + y1] == 0 and _cliff[x1 * N + y1] == 0:
		return false
	var fx := clampf(g.x - x0, 0.0, 1.0)
	var fy := clampf(g.y - y0, 0.0, 1.0)
	if lerpf(lerpf(_ramp[x0 * N + y0], _ramp[x1 * N + y0], fx), lerpf(_ramp[x0 * N + y1], _ramp[x1 * N + y1], fx), fy) >= 0.5:
		return false   # (a ramp: a way up, however steep)
	var e0 := lift_at(_g2w * g)
	var ex := (lift_at(_g2w * (g + Vector2(0.12, 0.0))) - e0) / 0.12
	var ey := (lift_at(_g2w * (g + Vector2(0.0, 0.12))) - e0) / 0.12
	return maxf(absf(ex), absf(ey)) >= TERRAIN.CLIFF_PX


# --- Tiled ground (TerrainTiles) -------------------------------------------------

## (worker thread) Levels from the heights, ramps between them - some by
## nature, and wherever needed so all the land can be reached from the landing
## site (land still cut off is filled in) - and the plots' level (elevation 0).
func _plan_tiles() -> void:
	_rock.fill(0)
	_crag = PackedByteArray()
	_crag.resize(N * N)
	var walk := PackedByteArray()
	walk.resize(N * N)
	for k in N * N:
		walk[k] = _walk_t[_terrain[k]]
	_lvl = TTILES.levels(N, _height, walk, _water_top)
	_plot_lvl = clampi(floori(maxf(0.0, _site_h - _water_top - 0.03) / TTILES.TERRACE), 0, 20)
	if _sky:   # (every platform hovers: level 1 or more, its underside toward the sky at 0)
		for k in N * N:
			if walk[k] == 1:
				_lvl[k] = maxi(_lvl[k], 1)
		_plot_lvl = maxi(_plot_lvl, 1)
	# The rim at the water's level (the cube's brick sides start there).
	for k in N * N:
		var i := k / N
		var j := k % N
		if mini(mini(i, j), mini(N - 1 - i, N - 1 - j)) < 3:
			_lvl[k] = 0
	# Plots, the landing site, village centres and gates: flat, at the plots' level.
	for c in _plot_cells:
		if c.x >= 0 and c.y >= 0 and c.x < N and c.y < N and walk[c.x * N + c.y] == 1:
			_lvl[c.x * N + c.y] = _plot_lvl
	for sp in _clear_spots:
		var r := ceili(float(sp[1]) + 2.0)
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var q: Vector2i = sp[0] + Vector2i(dx, dy)
				if q.x >= 0 and q.y >= 0 and q.x < N and q.y < N and walk[q.x * N + q.y] == 1 and Vector2(dx, dy).length() <= r:
					_lvl[q.x * N + q.y] = _lvl[sp[0].x * N + sp[0].y]
	var c0 := Vector2i(N / 2, N / 2)
	for dx in range(-10, 11):
		for dy in range(-10, 11):
			var q := c0 + Vector2i(dx, dy)
			if Vector2(dx, dy).length() <= 10.0 and walk[q.x * N + q.y] == 1:
				_lvl[q.x * N + q.y] = _plot_lvl
	# Ramps by nature: here and there along a ledge's foot.
	_rampd = PackedByteArray()
	_rampd.resize(N * N)
	for i in range(2, N - 2):
		for j in range(2, N - 2):
			var k := i * N + j
			if walk[k] == 0 or hash(Vector2i(i, j) * 7 + Vector2i(pdata["seed"], 3)) % 100 >= 9:
				continue
			for r in range(1, 5):
				if _ramp_fits(Vector2i(i, j), r, walk):
					_rampd[k] = r
					break
	_link_levels(walk)


## A ramp at c rising toward direction r fits: the tile beyond one level up,
## the one behind and both sides on c's level.
func _ramp_fits(c: Vector2i, r: int, walk: PackedByteArray) -> bool:
	var d: Vector2i = TTILES.RAMP_DIRS[r]
	var side := Vector2i(d.y, d.x)
	for q in [c + d, c - d, c + side, c - side]:
		if q.x < 0 or q.y < 0 or q.x >= N or q.y >= N or walk[q.x * N + q.y] == 0:
			return false
	var l := _lvl[c.x * N + c.y]
	var hi := c + d
	if _lvl[hi.x * N + hi.y] != l + 1 or _rampd[hi.x * N + hi.y] != 0:
		return false
	for q in [c - d, c + side, c - side]:
		if _lvl[q.x * N + q.y] != l:
			return false
	return not _plot_cells.has(c)


## Walking from tile a to its neighbour b (indices): the same level, or up or
## down a ramp. Cliffs are walls.
func _step_ok_t(a: int, b: int) -> bool:
	if _walk_t[_terrain[b]] == 0 or _rock[b] >= 128:
		return false
	var la := _lvl[a]
	var lb := _lvl[b]
	var d := Vector2i(b / N - a / N, b % N - a % N)
	if la == lb:
		# (a ramp's sides are stone faces: on and off it only at its ends)
		if _rampd[a] != 0 and _perp(TTILES.RAMP_DIRS[_rampd[a]], d):
			return false
		if _rampd[b] != 0 and _perp(TTILES.RAMP_DIRS[_rampd[b]], d):
			return false
		return true
	if lb == la + 1 and _rampd[a] != 0 and TTILES.RAMP_DIRS[_rampd[a]] == d:
		return true
	if la == lb + 1 and _rampd[b] != 0 and TTILES.RAMP_DIRS[_rampd[b]] == -d:
		return true
	return false


## Two grid steps at right angles.
static func _perp(p: Vector2i, q: Vector2i) -> bool:
	return p.x * q.x + p.y * q.y == 0


## (worker thread) Every bit of land reachable from the landing site: a
## breadth-first walk; where it meets land one level up or down that it can't
## reach, a ramp goes in (nearest first) and the walk goes on. Land it still
## can't reach (cut off by drops of two levels or more) is filled in.
func _link_levels(walk: PackedByteArray) -> void:
	var seen := PackedByteArray()
	seen.resize(N * N)
	var start := (N / 2) * N + N / 2
	var queue := PackedInt32Array([start])
	seen[start] = 1
	var cand := PackedInt32Array()      # pairs (from, to) one level apart
	var head := 0
	var ci := 0
	while true:
		while head < queue.size():
			var c := queue[head]
			head += 1
			var i := c / N
			var j := c % N
			for q in [c - N if i > 0 else -1, c + N if i < N - 1 else -1, c - 1 if j > 0 else -1, c + 1 if j < N - 1 else -1]:
				if q < 0 or seen[q] == 1 or walk[q] == 0:
					continue
				if _step_ok_t(c, q):
					seen[q] = 1
					queue.append(q)
				elif absi(int(_lvl[q]) - int(_lvl[c])) == 1:
					cand.append(c)
					cand.append(q)
		# A ramp to the nearest land not reached yet.
		var made := false
		while ci < cand.size():
			var a := cand[ci]
			var b := cand[ci + 1]
			ci += 2
			if seen[b] == 1:
				continue
			var lo := a if _lvl[a] < _lvl[b] else b
			var hi := b if lo == a else a
			var d := Vector2i(hi / N - lo / N, hi % N - lo % N)
			var r := TTILES.RAMP_DIRS.find(d)
			if r <= 0 or _rampd[lo] != 0 or _rampd[hi] != 0:
				continue
			_rampd[lo] = r
			seen[b] = 1
			queue.append(b)
			made = true
			break
		if not made:
			break
	for k in N * N:
		if walk[k] == 1 and seen[k] == 0:
			_rock[k] = 255   # (no way there)


## Walkable here on tiled ground: the tile, and - near its edges - the step
## to the tile beyond (a cliff edge keeps you MARGIN away).
func _tile_ground_ok(g: Vector2) -> bool:
	var c := Vector2i(clampi(roundi(g.x), 0, N - 1), clampi(roundi(g.y), 0, N - 1))
	var k := c.x * N + c.y
	if _walk_t[_terrain[k]] == 0 or _rock[k] >= 128:
		return false
	if _lvl.size() != N * N or _rampd.size() != N * N:
		return true   # (while the villages are planned: levels come after)
	var f := g - Vector2(c)
	var m := 0.5 - TTILES.MARGIN
	var sx := 1 if f.x > m else (-1 if f.x < -m else 0)
	var sy := 1 if f.y > m else (-1 if f.y < -m else 0)
	if sx != 0 and (c.x + sx < 0 or c.x + sx >= N or not _step_ok_t(k, k + sx * N)):
		return false
	if sy != 0 and (c.y + sy < 0 or c.y + sy >= N or not _step_ok_t(k, k + sy)):
		return false
	if sx != 0 and sy != 0:
		var q := k + sx * N + sy
		if _walk_t[_terrain[q]] == 0 or _rock[q] >= 128 or _lvl[q] != _lvl[k]:
			return false
	return true


## How high tiled ground stands (screen px): its level above the plots', up a
## ramp as you climb it.
func _tile_lift(g: Vector2) -> float:
	if _lvl.size() != N * N:
		return 0.0
	var c := Vector2i(clampi(roundi(g.x), 0, N - 1), clampi(roundi(g.y), 0, N - 1))
	var k := c.x * N + c.y
	var e := (int(_lvl[k]) - _plot_lvl) * TTILES.LEVEL_PX
	if _rampd[k] != 0:
		var d: Vector2i = TTILES.RAMP_DIRS[_rampd[k]]
		e += clampf((g - Vector2(c)).dot(Vector2(d)) + 0.5, 0.0, 1.0) * TTILES.LEVEL_PX
	return e


## The tile set (pdata "tiles") and the pieces its ground uses (TerrainTiles.ground_pieces).
var _tile_set_id := ""
var _tile_pieces: Array = []
var _decode_task := -1   # (TerrainTiles.predecode while the world is made)

## The ground from the tile set: a y-sorted TileMapLayer per level, raised by
## its level (above the plots' level) - higher levels drawn over lower; a tile
## whose front neighbours are lower is a cliff block (stacked down as far as
## they drop).
var _tile_ts: TileSet
## The ground's tile layers (TileGround) and the pictures they're shown as.
var tile_ground: Node2D
var ground_chunks: GroundChunks
## The ground as 3D geometry (Ground3D: the streamed worlds) - then there are no tile layers.
var ground3d: Ground3D
var ground_force := true          # the next update renders all the ground in view at once (a jump: set it)

## (worker thread) Every tile of the ground, as each level's TileMapLayer
## tile_map_data (2 bytes of header, then 12 bytes a cell: x, y, source, atlas
## x, atlas y, alternative) - set on the layers in one go (_build_tile_ground).
var _tile_data: Array = []           # PackedByteArray per level
const NPCS_A_FRAME := 2           # people coming into reach spawned a frame (_stream_plans)
const STRIP_CELLS := 3000           # a flat layer's tiles added a frame (_build_tile_ground)
## The set's water is open sky (TerrainTiles.is_sky): nothing drawn there, and
## the platforms stand at level 1 or more, their undersides toward it.
var _sky := false

func _tile_cells() -> void:
	var ti := _tile_set_id
	var src := {}
	for i in _tile_pieces.size():
		src[_tile_pieces[i]] = i
	var top := 0
	for k in N * N:
		top = maxi(top, _lvl[k])
	_tc = PackedInt32Array()
	# Water nearby (within 2 tiles, the cross): one pass, not per tile and neighbour.
	var wetk := PackedByteArray()
	wetk.resize(N * N)
	for k in N * N:
		wetk[k] = 1 - _walk_t[_terrain[k]]
	var near := PackedByteArray()   # 1: water within 2 (the cross); 2: land within 2 (for water)
	near.resize(N * N)
	for i in N:
		for j in N:
			var k := i * N + j
			var want := 1 - wetk[k]   # (the other kind)
			for o in [-2 * N, -N, N, 2 * N]:
				var q: int = k + o
				if q >= 0 and q < N * N and wetk[q] == want:
					near[k] = 1
					break
			if near[k] == 0:
				for dj in [-2, -1, 1, 2]:
					if j + dj >= 0 and j + dj < N and wetk[k + dj] == want:
						near[k] = 1
						break
	var piece_of := {}   # (role -> source id, looked up once; a role with no piece is left out)
	for role in ["deep", "shallow", "shore_corner", "shore_left", "shore_right", "block_corner", "block_left", "block_right"] + TTILES.RAMP_PIECES.slice(1) + TTILES.RIMS:
		var pn := TTILES.pc(ti, role)
		if pn != "" and src.has(pn):
			piece_of[role] = src[pn]
	var kinds: Array = pdata["terrain"].map(func(t): return t[3])
	var noise := FastNoiseLite.new()
	noise.seed = int(pdata["seed"]) + 11
	noise.frequency = 0.08
	var noise2 := FastNoiseLite.new()
	noise2.seed = int(pdata["seed"]) + 12
	noise2.frequency = 0.03
	for i in N:
		for j in N:
			var k := i * N + j
			var l := int(_lvl[k])
			var cell := Vector2i(i, j)
			if wetk[k] == 1:
				var wrole := "shallow" if near[k] == 1 else "deep"
				if piece_of.has(wrole):   # (open sky: nothing)
					_put(0, cell, piece_of[wrole])
				continue
			if _rampd[k] != 0:
				_put(l, cell, piece_of[TTILES.RAMP_PIECES[_rampd[k]]])
				continue
			# The front neighbours (grid +x: right-front, +y: left-front): lower ones show a cliff.
			var low_r := _front_drop(k, i < N - 1, k + N, Vector2i(1, 0), l)
			var low_l := _front_drop(k, j < N - 1, k + 1, Vector2i(0, 1), l)
			if low_r >= 0 or low_l >= 0:
				var piece := "block_corner" if low_r >= 0 and low_l >= 0 else ("block_right" if low_r >= 0 else "block_left")
				var bottom := mini(low_r if low_r >= 0 else l, low_l if low_l >= 0 else l)
				for b in range(bottom + 1, l + 1):
					_put(b, cell, piece_of[piece])
				continue
			# Flat ground: sand and shore by the water, grass and woods elsewhere.
			var water_l := i < N - 1 and wetk[k + N] == 1
			var water_y := j < N - 1 and wetk[k + 1] == 1
			# (lower ground behind it - or the open sky: its back edge drawn as a lip - TerrainTiles.RIMS)
			var back_l := i > 0 and ((wetk[k - N] == 0 and int(_lvl[k - N]) < l) or (_sky and wetk[k - N] == 1)) and _rampd[k - N] == 0
			var back_r := j > 0 and ((wetk[k - 1] == 0 and int(_lvl[k - 1]) < l) or (_sky and wetk[k - 1] == 1)) and _rampd[k - 1] == 0
			if (back_l or back_r) and not water_l and not water_y:
				_put(l, cell, piece_of["rim_lr" if back_l and back_r else ("rim_l" if back_l else "rim_r")])
			elif water_l and water_y and piece_of.has("shore_corner"):
				_put(l, cell, piece_of["shore_corner"])
			elif water_y and piece_of.has("shore_left"):
				_put(l, cell, piece_of["shore_left"])
			elif water_l and piece_of.has("shore_right"):
				_put(l, cell, piece_of["shore_right"])
			else:
				_put(l, cell, src[TTILES.ground_piece(ti, kinds[_terrain[k]], l, near[k] == 1, noise.get_noise_2d(i, j), noise2.get_noise_2d(i, j))])
	# Packed by layer - two a level: the flat tiles (drawn unsorted, so the
	# renderer batches them by quadrant), then the blocks and ramps (y-sorted:
	# their faces overlap the tiles in front) - count, place, then each
	# layer's slice behind its header.
	var flat := PackedByteArray()
	flat.resize(_tile_pieces.size())
	for i in _tile_pieces.size():
		var base := str(_tile_pieces[i]).substr(3)
		flat[i] = 1 if base in TTILES.FLAT or base in TTILES.RIMS else 0
	var layers := 2 * (top + 1)
	var counts := PackedInt32Array()
	counts.resize(layers)
	for e in range(0, _tc.size(), 4):
		counts[2 * _tc[e] + 1 - flat[_tc[e + 3]]] += 1
	var start := PackedInt32Array()
	start.resize(layers + 1)
	for l in layers:
		start[l + 1] = start[l] + counts[l]
	var at := start.duplicate()
	var big := PackedByteArray()
	big.resize(12 * (_tc.size() / 4))
	for e in range(0, _tc.size(), 4):
		var li: int = 2 * _tc[e] + 1 - flat[_tc[e + 3]]
		var o: int = 12 * at[li]
		at[li] += 1
		big.encode_s16(o, _tc[e + 1])
		big.encode_s16(o + 2, _tc[e + 2])
		big.encode_u16(o + 4, _tc[e + 3])
	_tc = PackedInt32Array()
	_tile_data = []
	for l in layers:
		_tile_data.append(PackedByteArray([0, 0]) + big.slice(12 * start[l], 12 * start[l + 1]))


var _tc := PackedInt32Array()        # (level, x, y, source) per tile placed

func _put(l: int, c: Vector2i, id: int) -> void:
	_tc.append(l)
	_tc.append(c.x)
	_tc.append(c.y)
	_tc.append(id)


## The ground's tiles: two TileMapLayers a level, raised by its level (higher
## levels drawn over lower) - the flat tiles unsorted (batched: a few draw
## calls a quadrant, not a canvas item a tile), then its blocks and ramps
## y-sorted over them - filled from _tile_data in one go.
func _build_tile_ground() -> void:
	var ts := _tile_ts if _tile_ts else TTILES.tile_set(_tile_pieces)
	var holder := Node2D.new()
	holder.name = "TileGround"
	holder.z_index = -10
	# Drawn as pictures (GroundChunks): the layers live in the ground's own world.
	if GroundChunks.enabled:
		ground_chunks = GroundChunks.new()
		add_child(ground_chunks)
		ground_chunks.host(holder)
	else:
		add_child(holder)
	tile_ground = holder
	for li in _tile_data.size():
		var data: PackedByteArray = _tile_data[li]
		if data.size() <= 2:
			continue   # (nothing on this layer)
		var l := li / 2
		var ysort := li % 2 == 1
		# A flat layer (its tiles never overlap) in strips of STRIP_CELLS, one a
		# frame: a whole layer (tens of thousands of tiles) in one frame stalled
		# the landing 60 ms. (The y-sorted ones stay whole: their order matters.)
		var cells := (data.size() - 2) / 12
		var per := cells if ysort else STRIP_CELLS
		for from in range(0, cells, per):
			var layer := TileMapLayer.new()
			layer.tile_set = ts
			layer.y_sort_enabled = ysort
			layer.position = Vector2(0, -(l - _plot_lvl) * TTILES.LEVEL_PX)
			layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			layer.tile_map_data = data if per >= cells else PackedByteArray([0, 0]) + data.slice(2 + 12 * from, 2 + 12 * mini(from + per, cells))
			holder.add_child(layer)
			await get_tree().process_frame
	_tile_data = []
	# The cube's brick sides under the rim (at the water's level).
	var e := 0.5
	var edge := Node2D.new()
	edge.set_script(preload("res://scripts/surface_edge.gd"))
	var up := Vector2(0, _plot_lvl * TTILES.LEVEL_PX)
	edge.corners = [_g2w * Vector2(-e, N - e) + up, _g2w * Vector2(N - e, N - e) + up, _g2w * Vector2(N - e, -e) + up]
	edge.z_index = -11
	add_child(edge)


## How far down a front neighbour drops (its level), or -1 if it doesn't
## (the same level or higher, water, or a ramp climbing up to this tile).
func _front_drop(k: int, inside: bool, q: int, d: Vector2i, l: int) -> int:
	if not inside:
		return -1
	if _walk_t[_terrain[q]] == 0:
		return 0 if _sky and l > 0 else -1   # (open sky in front: the platform's underside, down to its level 0)
	var lq := int(_lvl[q])
	if lq >= l:
		return -1
	if _rampd[q] != 0 and TTILES.RAMP_DIRS[_rampd[q]] == -d and lq == l - 1:
		return -1
	return lq


## What grows on a tiled planet's tile: [kind, colour, scale] - its trees,
## shrubs, rocks and the odd ruin (the tile set's pieces, kind "<set>_<piece>": TerrainTiles.SETS).
func _tile_flora(cell: Vector2i, kind: String, rng: RandomNumberGenerator) -> Array:
	var k := cell.x * N + cell.y
	if _rampd.size() == N * N and _rampd[k] != 0:
		return []
	var out := []
	var r := rng.randf()
	var w := Color.WHITE
	var ts: Dictionary = TTILES.SETS[_tile_set_id]
	var ti := _tile_set_id
	var pick := func(list: Array) -> String: return ti + "_" + str(list[rng.randi() % list.size()])
	if kind in ts["woods"]:
		if r < 0.28:
			out.append([pick.call(ts["wood_trees"]), w, rng.randf_range(0.85, 1.1)])
		elif r < 0.38:
			out.append([pick.call(ts["wood_shrubs"]), w, rng.randf_range(0.7, 0.95)])
	else:
		var ch: Array = ts["chances"]
		if r < ch[0]:
			out.append([pick.call(ts["trees"]), w, rng.randf_range(0.85, 1.1)])
		elif r < ch[0] + ch[1]:
			out.append([pick.call(ts["shrubs"]), w, rng.randf_range(0.6, 0.9)])
		elif r < ch[0] + ch[1] + ch[2]:
			out.append([pick.call(ts["rocks"]), w, rng.randf_range(0.6, 0.9)])
		elif r < ch[0] + ch[1] + ch[2] + ch[3]:
			out.append([pick.call(ts["ruins"]), w, 0.8])
	return out


## The ground-plane point drawn at a world (screen) point: the ground is
## lifted, so the point under the cursor lies further down the plane - the
## front-most one where hills overlap (a ray down the screen column: from
## the front, the first ground point drawn at or above w, then bisected).
func screen_to_ground(w: Vector2) -> Vector2:
	var f := func(t: float) -> float: return t - lift_at(w + Vector2(0, t))   # > 0: drawn below w
	var hi := 1400.0
	var t := hi
	var prev := t
	if f.call(t) <= 0.0:
		return w + Vector2(0, t)
	while t > -hi:
		prev = t
		t -= 6.0
		if f.call(t) <= 0.0:
			var a := t
			var b := prev
			for k in 10:
				var m := (a + b) * 0.5
				if f.call(m) <= 0.0:
					a = m
				else:
					b = m
			return w + Vector2(0, (a + b) * 0.5)
	return w


## Everything standing on the ground is drawn lifted by the ground's
## elevation under it (its position stays on the ground plane, where the game
## works): just before each frame is drawn, the canvas item of each node in
## group "surface_lift" (characters, things, bolts) is moved up. Scenery is
## lifted once, when it's made (_lift_static). The camera follows the drawn
## pilot.
var _lifted := {}   # node -> its global transform when last lifted
var _lift_k := 0

func _apply_lifts() -> void:
	if not is_inside_tree() or not visible or _rock.size() != N * N:
		return
	var vr := view_rect.grow(300.0) if view_rect.has_area() else Rect2(-1e9, -1e9, 2e9, 2e9)
	for n in get_tree().get_nodes_in_group("surface_lift"):
		var c := n as Node2D
		if c == null or not vr.has_point(c.global_position):
			continue   # (only what's in view is drawn: its lift only matters there)
		var gx: Transform2D = c.global_transform
		if _lifted.get(c) == gx:
			continue   # (not moved since: its drawn transform still has the lift - Godot sends a node's own only when it changes)
		if not is_ancestor_of(c):
			continue
		_lifted[c] = gx
		var xf: Transform2D = c.transform
		xf.origin.y -= lift_at(gx.origin)
		RenderingServer.canvas_item_set_transform(c.get_canvas_item(), xf)
	_lift_k += 1
	if _lift_k >= 30 or _lifted.size() > 600:
		_lift_k = 0
		_lifted.clear()   # (all lifted afresh now and then: the ones gone since, one re-added to the tree)
	_move_window()
	if is_instance_valid(pilot):
		var cam := pilot.get_node_or_null("Camera2D") as Camera2D
		if cam:
			cam.offset.y = -lift_at(pilot.global_position)
	if ground3d:
		ground3d.sync()


## Scenery doesn't move: lifted once (see _apply_lifts).
func _lift_static(c: Node2D) -> void:
	var xf := c.transform
	xf.origin.y -= lift_at(c.global_position)
	RenderingServer.canvas_item_set_transform(c.get_canvas_item(), xf)


## Bilinear height between cell centres (matches the shader's linear filter).
func _height_interp(g: Vector2) -> float:
	var x0 := clampi(floori(g.x), 0, N - 1)
	var y0 := clampi(floori(g.y), 0, N - 1)
	var x1 := mini(x0 + 1, N - 1)
	var y1 := mini(y0 + 1, N - 1)
	var fx := clampf(g.x - x0, 0.0, 1.0)
	var fy := clampf(g.y - y0, 0.0, 1.0)
	var a := lerpf(_height[x0 * N + y0], _height[x1 * N + y0], fx)
	var b := lerpf(_height[x0 * N + y1], _height[x1 * N + y1], fx)
	return lerpf(a, b, fy)


## The ground is one polygon covering the map, painted by
## shaders/ground.gdshader from a smoothed height map. A (hidden) isometric
## TileMapLayer is kept just for grid <-> world conversions.
func _build_tilemap() -> void:
	var tileset := TileSet.new()
	tileset.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tileset.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tileset.tile_size = TILE
	tilemap = TileMapLayer.new()
	tilemap.tile_set = tileset
	tilemap.visible = false
	add_child(tilemap)
	var o := tilemap.map_to_local(Vector2i(0, 0))
	var bx := tilemap.map_to_local(Vector2i(1, 0)) - o
	var by := tilemap.map_to_local(Vector2i(0, 1)) - o
	_g2w = Transform2D(bx, by, o)
	_world_to_grid = _g2w.affine_inverse()


## The ground: one polygon over the whole map, painted by the ground shader
## from the height map (one texel per tile; built on the worker thread as
## bytes - see _generate_world). The GPU only shades what's on screen.
func _build_ground() -> void:
	_height_img = Image.create_from_data(N, N, false, Image.FORMAT_RGBAF, _ground_data.to_byte_array())
	_height_tex = ImageTexture.create_from_image(_height_img)
	_ground_data = PackedFloat32Array()
	if _tiled:
		return   # (the tiles: _build_tile_ground, in slices)
	var height_tex := _height_tex
	var grid_to_world := _g2w
	var inv := _world_to_grid

	var types: Array = pdata["terrain"]
	var colors := PackedColorArray()
	var kinds := PackedInt32Array()
	for t in types:
		colors.append(t[1])
		kinds.append(Planets.GROUND_KINDS.find(t[3]))
	var thresholds := PackedFloat32Array(pdata["thresholds"])

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ground.gdshader")
	mat.set_shader_parameter("height_map", height_tex)
	mat.set_shader_parameter("grid_n", float(N))
	mat.set_shader_parameter("inv_x", inv.x)
	mat.set_shader_parameter("inv_y", inv.y)
	mat.set_shader_parameter("inv_o", inv.origin)
	mat.set_shader_parameter("count", types.size())
	mat.set_shader_parameter("colors", colors)
	mat.set_shader_parameter("kinds", kinds)
	mat.set_shader_parameter("thresholds", thresholds)
	mat.set_shader_parameter("seed", float(pdata["seed"] % 97))
	mat.set_shader_parameter("rock_color", pdata.get("rock_color", ROCK_COLOR))

	mat.set_shader_parameter("rock_solid", TERRAIN.ROCK_SOLID)
	mat.set_shader_parameter("cliff_px", TERRAIN.CLIFF_PX)
	mat.set_shader_parameter("terrace_h", TERRAIN.TERRACE)
	mat.set_shader_parameter("step_px", TERRAIN.STEP)
	mat.set_shader_parameter("cliff_w", TERRAIN.CLIFF_W)
	mat.set_shader_parameter("crag_h", TERRAIN.CRAG_H)
	mat.set_shader_parameter("rim_tiles", TERRAIN.RIM)
	mat.set_shader_parameter("water_top", _water_top)
	mat.set_shader_parameter("site_h", _site_h)
	mat.set_shader_parameter("rim_lift", TERRAIN.rim_lift(_water_top, _site_h))
	mat.set_shader_parameter("t0", 0.0)
	mat.set_shader_parameter("g2w_x", grid_to_world.x)
	mat.set_shader_parameter("g2w_y", grid_to_world.y)
	mat.set_shader_parameter("g2w_o", grid_to_world.origin)
	mat.set_shader_parameter("win_size", float(FINE_W))
	_coarse_mat = mat
	_fine_mat = mat.duplicate()
	_fine_mat.set_shader_parameter("fine_mesh", true)
	# The ground: a mesh with a vertex at every tile corner, lifted by the
	# shader into hills (SurfaceTerrain.elevation).
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _ground_mesh[0]
	arrays[Mesh.ARRAY_INDEX] = _ground_mesh[1]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ground_mesh = []
	var ground := MeshInstance2D.new()
	ground.mesh = mesh
	ground.material = mat
	var e := 0.5
	ground.z_index = -10
	add_child(ground)
	# The fine window over it (placed by the shader: never culled).
	var warr := []
	warr.resize(Mesh.ARRAY_MAX)
	warr[Mesh.ARRAY_VERTEX] = _window_mesh[0]
	warr[Mesh.ARRAY_INDEX] = _window_mesh[1]
	var wmesh := ArrayMesh.new()
	wmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, warr)
	_window_mesh = []
	var fine := MeshInstance2D.new()
	fine.name = "GroundFine"
	fine.mesh = wmesh
	fine.material = _fine_mat
	fine.z_index = -10
	add_child(fine)
	RenderingServer.canvas_item_set_custom_rect(fine.get_canvas_item(), true, Rect2(-1e7, -1e7, 2e7, 2e7))
	_move_window()
	# The map is the top of a cube: its two front faces are orange brick.
	var edge := Node2D.new()
	edge.set_script(preload("res://scripts/surface_edge.gd"))
	var up := Vector2(0, -TERRAIN.rim_lift(_water_top, _site_h))   # (the rim's elevation)
	edge.corners = [grid_to_world * Vector2(-e, N - e) + up, grid_to_world * Vector2(N - e, N - e) + up, grid_to_world * Vector2(N - e, -e) + up]
	edge.z_index = -11
	add_child(edge)


func _build_background() -> void:
	var bg := CanvasLayer.new()
	bg.layer = -1
	bg.visible = not prebuilding
	add_child(bg)
	if _sky and GasSky.available():
		# A gas giant's painted cloud deck under the platforms (GasSky: the
		# bands scrolling at their own speeds, storms drifting along them).
		var deck := GasSky.new()
		deck.name = "GasSky"
		deck.origin = _cell_pos(Vector2i(N / 2, N / 2))   # (the pad: the stack centred on the window there)
		bg.add_child(deck)
		return
	if _sky:
		# (no painted bands: shaders/gas_sky.gdshader - banded, slowly drifting)
		var sky := ColorRect.new()
		sky.name = "GasSky"
		sky.set_anchors_preset(Control.PRESET_FULL_RECT)
		sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sky.material = ShaderMaterial.new()
		sky.material.shader = preload("res://shaders/gas_sky.gdshader")
		sky.material.set_shader_parameter("tint", pdata.get("sky_color", Color(0.85, 0.55, 0.3)))
		bg.add_child(sky)
		return
	var stars := Node2D.new()
	stars.set_script(preload("res://scripts/starfield.gd"))
	bg.add_child(stars)


# --- Objects ---------------------------------------------------------------------

func _cell_pos(cell: Vector2i) -> Vector2:
	return _g2w * Vector2(cell)   # (= tilemap.map_to_local; plain maths, safe on worker threads)


## The tile under a world point (= tilemap.local_to_map, thread-safe).
func _cell_at(world: Vector2) -> Vector2i:
	var g := _world_to_grid * world
	return Vector2i(roundi(g.x), roundi(g.y))


## A random walkable cell at least `min_dist` cells from every cell in `avoid`.
func _free_cell(avoid: Array, min_dist: float, tries := 200) -> Vector2i:
	for k in tries:
		var c := Vector2i(_rng.randi_range(3, N - 4), _rng.randi_range(3, N - 4))
		if not walkable_cell(c) or _blocked_cells.has(c):
			continue
		var ok := true
		for a in avoid:
			if Vector2(c).distance_to(Vector2(a)) < min_dist:
				ok = false
				break
		if ok:
			return c
	return Vector2i(N / 2, N / 2)


func _place_everything() -> void:
	var center := Vector2i(N / 2, N / 2)
	lander = PROPS.Lander.new()
	var pl: Dictionary = state.get("player", {})
	lander.ship_class = str(pl.get("ship_class", "player"))
	lander.look = pl.get("ship_look", {})
	lander.position = _cell_pos(center)
	objects.add_child(lander)

	pilot = PROPS.Pilot.new()
	pilot.surface = self
	pilot.stamina = Stamina.of(state["player"])
	Skills.state(state["player"])       # (its skills: made the first time, the starting ones on the toolbar)
	Sfx.warm("skill")
	# Your loadout (Gear) and the planet's environment (Planets.environment:
	# volcanic heat slows your healing, ice your walking).
	refresh_gear()
	pilot.position = _cell_pos(center) + Vector2(0, 90)
	# A loaded save made down here: where you stood.
	var at: Array = SaveGame.resume.get("pos", []) if str(SaveGame.resume.get("planet", "")) == planet_id else []
	if at.size() == 2:
		pilot.position = Vector2(float(at[0]), float(at[1]))
	SaveGame.resume = {}
	objects.add_child(pilot)
	var cam := Camera2D.new()
	cam.enabled = not prebuilding
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	pilot.add_child(cam)

	if not _layout.is_empty():
		await _place_from_layout()
		await _breathe(0.6, "Raising the Minoan buildings")
		if _layout_off > 0:
			_veg_exclude = _layout_rect   # (the land around a smaller saved layout gets streamed scenery)
		return
	# The buildings and citizens around the landing pad (the rest appear as you go).
	await _stream_plans(true)


# --- Planning the planet (worker thread) ---------------------------------------------

## Buildings planned across the planet (built when you come near):
## {spec, built: BuiltBuilding or null}. Citizens: {pos, variant, home, spawned}.
var _plans: Array = []
var _npc_plans: Array = []
var _plot_cells := {}               # planned plots (+3 tiles): no scenery
var _clear_spots: Array = []        # [cell, radius]: open ground kept free of scenery
var _site_h := 0.0
## Villages: one region in REGION x REGION tiles in about VILLAGE_CHANCE.
const REGION := 110
const VILLAGE_CHANCE := 0.45

func _plan_world() -> void:
	var center := Vector2i(N / 2, N / 2)
	_site_h = _site_height()
	_level_disc(center, 9.0, 14.0)   # the landing site: at the site height (no lift, like the plots)
	_add_clear_spot(center, 3.2)
	if pdata.get("villages", true):
		# The landing village: the palace by the pad, a warehouse and a temple.
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		_plan_village(center, center + Vector2i(dir * 28.0), true, 0)
		# Villages across the planet.
		var vid := 1
		for gx in N / REGION:
			for gy in N / REGION:
				var c := Vector2i(gx * REGION + REGION / 2, gy * REGION + REGION / 2)
				c += Vector2i(_rng.randi_range(-25, 25), _rng.randi_range(-25, 25))
				if Vector2(c).distance_to(Vector2(center)) < REGION * 0.8 or _rng.randf() > VILLAGE_CHANCE:
					continue
				_plan_village(c, c, _rng.randf() < 0.35, vid)
				vid += 1
	elif pdata.get("industry", true):
		_plan_industry()   # (gas giants: refineries, factories and depots on the platforms)
	# (neither - the volcanic planet: no buildings at all, only the wilds)
	# Pirate bands roaming the wilds.
	for b in PIRATE_BANDS:
		var c := Vector2i(_rng.randi_range(20, N - 21), _rng.randi_range(20, N - 21))
		if Vector2(c).distance_to(Vector2(center)) < 30.0:
			continue
		_plan_pirate_band(c, _rng.randi_range(2, 4))


# --- Industry (gas giants: no villages, machinery) -------------------------------------

## Industrial sites on a platform planet (pdata "villages": false): clusters of
## the tile set's structures - refineries (tanks, pipes, stacks), factories
## (machinery, cranes, containers), depots (containers, barrels, a robot) -
## each on a plot levelled flat (its cells in _plot_cells: no stray scenery).
## Planned on the worker thread; the pieces are placed with the chunks' scenery
## (_chunk_flora). Each: [piece, tile offset x, tile offset y, scale].
const INDUSTRY := {
	"refinery": [["fuel_tank", -2, -2, 1.0], ["fuel_tank", 2, -2, 1.0], ["fuel_tank", -2, 2, 1.0], ["fuel_tank", 2, 2, 1.0],
		["pipes", 0, 0, 1.0], ["vent_stack", 0, -3, 1.0], ["cooling_tower", 3, 0, 1.0], ["machinery", -3, 0, 0.9], ["lamp_post", 0, 3, 0.9]],
	"factory": [["machinery", -2, -1, 1.0], ["machinery", 0, -2, 1.0], ["machinery", 2, -1, 1.0], ["crane", 0, 1, 1.0],
		["containers", -3, 2, 0.9], ["containers", 3, 2, 0.9], ["crate", -1, 3, 0.8], ["lamp_post", 2, -3, 0.9], ["vent_stack", -3, -3, 0.9]],
	"depot": [["containers", -2, -2, 1.0], ["containers", 1, -2, 1.0], ["containers", -2, 1, 1.0], ["barrels", 2, 1, 0.9],
		["crate", 0, 0, 0.8], ["robot", 2, -1, 0.9], ["lamp_post", -3, 0, 0.9], ["container_fallen", 1, 3, 0.9]],
	"relay": [["antenna", 0, 0, 1.1], ["radar", 2, -2, 1.0], ["beacon", -2, 2, 1.0], ["machinery", -2, -2, 0.9], ["railing", 2, 2, 0.9]],
}
const INDUSTRY_SITES := 14
const INDUSTRY_R := 4               # tiles: the plot's radius
var _industry: Array = []           # {kind, cell}

func _plan_industry() -> void:
	_industry = []
	var center := Vector2i(N / 2, N / 2)
	var kinds := INDUSTRY.keys()
	var tries := 0
	while _industry.size() < INDUSTRY_SITES and tries < 400:
		tries += 1
		var c := Vector2i(_rng.randi_range(12, N - 13), _rng.randi_range(12, N - 13))
		if Vector2(c).distance_to(Vector2(center)) < 24.0:
			continue
		if _industry.any(func(s): return Vector2(s["cell"]).distance_to(Vector2(c)) < 22.0):
			continue
		var ok := true
		for dx in range(-INDUSTRY_R, INDUSTRY_R + 1):
			for dy in range(-INDUSTRY_R, INDUSTRY_R + 1):
				var q := c + Vector2i(dx, dy)
				if _walk_t[_terrain[q.x * N + q.y]] == 0:
					ok = false
		if not ok:
			continue
		var r := Rect2i(c - Vector2i(INDUSTRY_R - 1, INDUSTRY_R - 1), Vector2i(2 * INDUSTRY_R - 1, 2 * INDUSTRY_R - 1))
		_clear_site(r)   # (levelled flat, no crags)
		for dx in range(-INDUSTRY_R, INDUSTRY_R + 1):
			for dy in range(-INDUSTRY_R, INDUSTRY_R + 1):
				_plot_cells[c + Vector2i(dx, dy)] = true
		_industry.append({"kind": kinds[_industry.size() % kinds.size()], "cell": c})


## An industrial site's pieces in a chunk: [kind, colour, scale, variant, pos].
func _industry_in(area: Rect2i, out: Array) -> void:
	var ti := _tile_set_id
	for site in _industry:
		var c: Vector2i = site["cell"]
		if not area.grow(INDUSTRY_R).has_point(c):
			continue
		var n := 0
		for it in INDUSTRY[site["kind"]]:
			n += 1
			var cell: Vector2i = c + Vector2i(int(it[1]), int(it[2]))
			if not area.has_point(cell):
				continue
			var h := hash([int(pdata["seed"]), c.x, c.y, n])
			var piece: String = str(it[0]) + ("_b" if h % 2 == 1 else "")   # (either sheet's drawing)
			out.append([ti + "_" + piece, Color.WHITE, float(it[3]), h, _cell_pos(cell)])


# --- Wildlife ----------------------------------------------------------------------------

## Animals planned across the planet (SurfaceCreature.FAUNA for its terrain
## set): {species, pos, home, node (while near you), dead}. They come out within
## BUILD_R tiles of you and go (where they wandered to noted) beyond FAUNA_OUT.
var _fauna_plans: Array = []
var _fauna_t := 0.0
const FAUNA_OUT := BUILD_R + 16

## (worker thread) Herds, packs and loners on open ground.
func _plan_fauna() -> void:
	_fauna_plans = []
	var table: Array = SurfaceCreature.FAUNA.get(str(pdata.get("tiles", "")), [])
	if table.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(planet_id + ":fauna")
	var center := Vector2i(N / 2, N / 2)
	var towns: Array = [center] + _village_spots
	for row in table:
		for g in int(row[1]) * SurfaceCreature.DENSITY:
			var c := _fauna_cell(rng, str(row[4]), towns, center, g)
			if c == Vector2i(-1, -1):
				continue
			var home := _cell_pos(c)
			for k in rng.randi_range(int(row[2]), int(row[3])):
				var pos := home + Vector2(rng.randf_range(-90, 90), rng.randf_range(-45, 45))
				if not _ground_ok(pos):
					pos = home
				_fauna_plans.append({"species": str(row[0]), "pos": pos, "home": home, "node": null, "dead": false})


func _fauna_cell(rng: RandomNumberGenerator, where: String, towns: Array, center: Vector2i, g: int) -> Vector2i:
	for attempt in 40:
		var c: Vector2i
		if where == "village":   # (one herd a village in turn, the pad's last)
			var t: Vector2i = towns[(g + 1) % towns.size()]
			c = t + Vector2i(Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10.0, 24.0))
		else:
			c = Vector2i(rng.randi_range(10, N - 11), rng.randi_range(10, N - 11))
		if c.x < 4 or c.y < 4 or c.x > N - 5 or c.y > N - 5 or _plot_cells.has(c):
			continue
		if where == "wild" and towns.any(func(t): return Vector2(t).distance_to(Vector2(c)) < 30.0):
			continue
		if Vector2(c).distance_to(Vector2(center)) < 8.0 or not _ground_ok(_cell_pos(c)):
			continue
		return c
	return Vector2i(-1, -1)


## A species' entry in your bestiary ({seen, kills}; state["player"]["bestiary"]).
func _bestiary_entry(sp: String) -> Dictionary:
	var player: Dictionary = state["player"]
	if not player.has("bestiary"):
		player["bestiary"] = {}
	if not player["bestiary"].has(sp):
		player["bestiary"][sp] = {}
	return player["bestiary"][sp]


## The animals near you come out; those far away go (noting where they were).
## The ones you've come close to are in your bestiary.
func _stream_fauna() -> void:
	if pilot == null:
		return
	for c in creatures:
		if is_instance_valid(c) and not c.dead and c.position.distance_to(pilot.position) < 700.0:
			var e: Dictionary = _bestiary_entry(c.species)
			e["seen"] = true
	var here := _cell_at(pilot.position)
	for f in _fauna_plans:
		if f["dead"]:
			continue
		var n: Node2D = f["node"]
		if n != null:
			if not is_instance_valid(n):
				f["node"] = null
			elif _cell_at(n.position).distance_to(here) > FAUNA_OUT:
				if _ground_ok(n.position):
					f["pos"] = n.position
				f["home"] = n.home
				creatures.erase(n)
				n.queue_free()
				f["node"] = null
		elif _cell_at(f["pos"]).distance_to(here) <= BUILD_R and gen_ready(_cell_at(f["pos"])):
			if not _ground_ok(f["pos"]):
				f["pos"] = _nearest_walkable(f["pos"])   # (planned before the chunk's ledges were known)
			var c := SurfaceCreature.make(f["species"], str(pdata["tiles"]))
			c.surface = self
			c.position = f["pos"]
			c.home = f["home"]
			c.plan = f
			objects.add_child(c)
			creatures.append(c)
			f["node"] = c


# --- Teleport gates ---------------------------------------------------------------------

## Teleport gates (TeleportGate): {cell, name, node (null until you come near)} -
## by the landing pad, by every village, and out in the wilds; any one takes you
## to any other (open_gate_map -> SurfaceMap's gates mode -> teleport_to).
var gates: Array = []
var _village_spots: Array = []      # (where villages were planned: a gate goes by each)
const GATE_NAMES := ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota", "Kappa",
	"Lambda", "Mu", "Nu", "Xi", "Omicron", "Pi", "Rho", "Sigma", "Tau", "Upsilon", "Phi", "Chi", "Psi", "Omega"]
const WILD_GATES := 6               # out in the wilds (besides the pad's and the villages')
const GATE_APART := 45.0            # tiles between gates

## (worker thread) Where the gates stand: open, walkable ground off the plots,
## kept clear of scenery.
func _plan_gates() -> void:
	gates = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(planet_id + ":gates")
	var center := Vector2i(N / 2, N / 2)
	var spots: Array = [[center, 8, 14]]                 # [near, min, max] tiles
	for v in _village_spots:
		spots.append([v, 10, 22])
	for k in WILD_GATES * 4:
		spots.append([Vector2i(rng.randi_range(40, N - 41), rng.randi_range(40, N - 41)), 0, 12])
	var wild := 0
	for sp in spots:
		if gates.size() >= GATE_NAMES.size():
			break
		var is_wild: bool = sp[1] == 0
		if is_wild and wild >= WILD_GATES:
			continue
		var cell := _gate_cell(sp[0], sp[1], sp[2], rng)
		if cell == Vector2i(-1, -1):
			continue
		if gates.any(func(g): return Vector2(g["cell"]).distance_to(Vector2(cell)) < GATE_APART):
			continue
		var name: String = "Gate " + GATE_NAMES[gates.size()]
		gates.append({"cell": cell, "name": name, "node": null})
		_add_clear_spot(cell, 2.6)
		if is_wild:
			wild += 1


func _gate_cell(near: Vector2i, r0: int, r1: int, rng: RandomNumberGenerator) -> Vector2i:
	for attempt in 60:
		var a := rng.randf() * TAU
		var d := rng.randf_range(r0, r1)
		var c := near + Vector2i(roundi(cos(a) * d), roundi(sin(a) * d))
		if c.x < 12 or c.y < 12 or c.x > N - 13 or c.y > N - 13:
			continue
		if Vector2(c).distance_to(Vector2(N / 2, N / 2)) > N * 0.5 * 0.8 or Vector2(c).distance_to(Vector2(N / 2, N / 2)) < 6.0:
			continue
		var ok := true
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var q := c + Vector2i(dx, dy)
				if _plot_cells.has(q) or not _cell_walkable_h(q):
					ok = false
		for p in _plans:
			if _plan_rect(p).grow(3).has_point(c):
				ok = false
		if not _layout.is_empty() and _layout_rect.grow(4).has_point(c):
			ok = false   # (a saved layout's buildings)
		if ok:
			return c
	return Vector2i(-1, -1)


## (worker thread) Walkable ground at a cell, from its height.
func _cell_walkable_h(c: Vector2i) -> bool:
	var h := _height[c.x * N + c.y]
	var t := 0
	while t < _th.size() and h > _th[t]:
		t += 1
	return t < _walk_t.size() and _walk_t[t] == 1 and not _rock_cell(c)


## The gates near you stand (built as you come near, like the buildings).
func _stream_gates() -> void:
	var here := _cell_at(pilot.position)
	for i in gates.size():
		var g: Dictionary = gates[i]
		if g["node"] == null and Vector2(g["cell"]).distance_to(Vector2(here)) <= BUILD_R * 1.5 and gen_ready(g["cell"]):
			var gate := TeleportGate.new().setup(g["name"], i)
			gate.position = _cell_pos(g["cell"])
			objects.add_child(gate)
			g["node"] = gate


## A gate was clicked: the portal network's map.
func open_gate_map(gate: TeleportGate) -> void:
	Sfx.play("space/gate_hum", -6.0)
	var known := gates.filter(func(g): return fog == null or fog.explored(Vector2(g["cell"]) + Vector2(0.5, 0.5))).size()
	if known <= 1:
		show_prompt("%s: no other gate discovered yet - explore to find more." % gate.gate_name, 3.0)
	if surface_map != null:
		surface_map.open_gates(gate.index)


## Through the portal: a flash, and you step out in front of gate i.
func teleport_to(i: int) -> void:
	if i < 0 or i >= gates.size():
		return
	var g: Dictionary = gates[i]
	if fog != null and not fog.explored(Vector2(g["cell"]) + Vector2(0.5, 0.5)):
		return   # (an undiscovered gate: not in the network yet)
	if level != 0:
		_set_level(0, null)
	_target_thing = null
	_pending_target = []
	_far_goal = Vector2.INF
	pilot.path = PackedVector2Array()
	pilot.moving = false
	pilot.position = _cell_pos(g["cell"]) + Vector2(0, 70)
	stream_area(Rect2i(g["cell"] - Vector2i(24, 24), Vector2i(49, 49)))   # (the ground there first, if it isn't in yet)
	ground_force = true   # (the ground round where you come out, at once)
	_nav_dirty = true
	_stream_gates()
	Sfx.play("space/jump", -4.0)
	var flash := ColorRect.new()
	flash.color = Color(0.6, 0.85, 1.0, 0.85)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.add_child(flash)
	add_child(layer)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.7)
	tw.tween_callback(layer.queue_free)
	show_prompt("Through the portal: %s" % g["name"], 2.5)
	GameLog.post("Teleported to %s." % g["name"], "info")


## Pirate bands: this many roam each planet (plus one near every village).
const PIRATE_BANDS := 23            # (a quarter of the 880-tile planet's 90: the same density)

func _plan_pirate_band(c: Vector2i, count: int) -> void:
	var home := _cell_pos(c.clamp(Vector2i(8, 8), Vector2i(N - 9, N - 9)))
	for k in count:
		var pos := home + Vector2(_rng.randf_range(-160, 160), _rng.randf_range(-80, 80))
		if not _ground_ok(pos):
			pos = home
		if not _ground_ok(pos):
			continue
		_npc_plans.append({"pos": pos, "variant": _rng.randi_range(0, 9999), "home": home, "spawned": false, "kind": "pirate"})


## A village: maybe a palace (near `palace_near`), a warehouse and a temple
## (near `near`), each on a levelled plot, and its citizens.
func _plan_village(palace_near: Vector2i, near: Vector2i, palace: bool, vid: int) -> void:
	_village_spots.append(near)
	var homes: Array = []
	if palace:
		var pr := _find_clear_site(Vector2i(16, 14), palace_near, 22)
		if pr.size != Vector2i.ZERO:
			_clear_site(pr)
			var x0 := pr.position.x
			var y0 := pr.position.y
			var x1 := pr.end.x - 1
			var y1 := pr.end.y - 1
			var cols := []
			for c in [Vector2i(1, 1), Vector2i(4, 1), Vector2i(1, 11), Vector2i(4, 11),
					Vector2i(8, 8), Vector2i(12, 8), Vector2i(8, 11), Vector2i(12, 11)]:
				cols.append([x0 + c.x, y0 + c.y])
			_add_plan({"rect": [x0, y0, 16, 14], "material": "minoan", "style": "palace", "title": "%s palace" % _culture_name(),
				"doors": [[x0 + 3, y1, "sw"], [x1, y0 + 10, "se"], [x0 + 10, y0, "ne"]],
				"inner": [["i", x0 + 6, y0, y1, y0 + 6], ["j", y0 + 6, x0 + 6, x1, x0 + 10]],
				"mosaic": [x0 + 1, y0 + 4, 4, 6], "columns": cols})
	var styles := ["warehouse", "temple"]
	for hi in styles.size():
		var size: Vector2i = [Vector2i(13, 12), Vector2i(12, 12)][hi]
		var hr := _find_clear_site(size, near, 20)
		if hr.size == Vector2i.ZERO:
			continue
		_clear_site(hr)
		var door := Vector2i(hr.position.x + size.x / 2, hr.end.y - 1)
		_add_plan({"rect": [hr.position.x, hr.position.y, size.x, size.y], "material": "minoan", "style": styles[hi],
			"title": "%s %s" % [_culture_name(), styles[hi]], "doors": [[door.x, door.y, "sw"]],
			"inner": _divider(hr, [[door, "sw"]]), "mosaic": [], "columns": []})
		homes.append(hr.get_center())
	_add_clear_spot(near, 4.0)
	# Citizens: two living in each house, the rest about the village.
	var count := 9 if vid == 0 else 4
	for k in count:
		var home := _cell_pos(near)
		var spread := Vector2(120, 60)
		if k / 2 < homes.size():
			home = _cell_pos(homes[k / 2])
			spread = Vector2(40, 20)
		var pos := home + Vector2(_rng.randf_range(-spread.x, spread.x), _rng.randf_range(-spread.y, spread.y))
		if not _ground_ok(pos):
			pos = home
		_npc_plans.append({"pos": pos, "variant": k + vid * 9, "home": home, "spawned": false, "kind": ""})
	# Pirates prowl near every village (a band a little way out).
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(30.0, 38.0) if vid == 0 else _rng.randf_range(18.0, 26.0)
	_plan_pirate_band(near + Vector2i(Vector2.from_angle(ang) * dist), 2 if vid == 0 else 3)


func _add_plan(spec: Dictionary) -> void:
	_plans.append({"spec": spec, "built": null})
	var r := Rect2i(spec["rect"][0], spec["rect"][1], spec["rect"][2], spec["rect"][3])
	var g := r.grow(3)
	for i in range(g.position.x, g.end.x):
		for j in range(g.position.y, g.end.y):
			_plot_cells[Vector2i(i, j)] = true


func _plan_rect(p: Dictionary) -> Rect2i:
	var r: Array = p["spec"]["rect"]
	return Rect2i(r[0], r[1], r[2], r[3])


# --- Streaming (main thread) ----------------------------------------------------------

## Builds the planned buildings and citizens near you (all within BUILD_R at
## once while loading; otherwise one building a frame).
var _plans_k := 0
var _plans_hot := false   # (villagers still to come in: every frame till they're all out)

func _stream_plans(all_now := false) -> void:
	if not all_now and _raising.is_empty() and not _plans_hot:
		_plans_k = (_plans_k + 1) % 8
		if _plans_k != 0:
			return   # (nothing under way: what's come in range looked for every 8th frame)
	_plans_hot = false
	_stream_gates()
	var here := _cell_at(pilot.position)
	if all_now:
		while _raise_step():   # (one half raised: finished first - else it'd be raised twice)
			pass
	var busy := not all_now and _raise_step()   # (a building going up: its next step this frame)
	for p in _plans:
		if busy:
			break
		if p["built"] != null:
			continue
		var r := _plan_rect(p)
		if Vector2(r.get_center()).distance_to(Vector2(here)) > BUILD_R:
			continue
		if not gen_ready_rect(r.grow(3)):
			continue   # (its ground not made yet: later - its pieces' pictures never waited for: placeholders)
		_raising = {"plan": p, "step": 0}
		if not all_now:
			_raise_step()
			break
		# (While loading: a step a frame too - the landing animation plays meanwhile.)
		while _raise_step():
			if _loading:
				await get_tree().process_frame
		await _breathe(0.6, "Raising the Minoan buildings")
	var spawned := 0
	for n in _npc_plans:
		if not all_now and spawned >= NPCS_A_FRAME:
			_plans_hot = true
			break   # (the rest next frame: a village's sixteen at once was a 40 ms frame)
		if not n["spawned"] and _cell_at(n["pos"]).distance_to(here) <= BUILD_R and gen_ready(_cell_at(n["pos"])):
			spawned += 1
			n["spawned"] = true
			if not _ground_ok(n["pos"]):
				n["pos"] = _nearest_walkable(n["pos"])   # (planned before the cliffs were known)
			_spawn_npc(n["pos"], n["variant"], n["home"], str(n.get("kind", "")))
			if all_now and _loading and spawned % NPCS_A_FRAME == 0:
				await get_tree().process_frame   # (loading: the landing animation plays on)


## Plants, rocks and crystals for one chunk (worker thread): every walkable
## cell rolls for scenery based on its terrain kind (forests are dense,
## beaches get palms, the moon gets boulders and pebbles, ice gets shards and
## crystals) - never on building plots or the open ground kept by the pad and
## villages. The same chunk always grows the same: [kind, colour, scale, variant, pos].
var _veg_exclude := Rect2i()

func _chunk_flora(key: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(pdata["seed"]), key.x, key.y])
	var leaf: Color = pdata["prop_color"]
	var area := Rect2i(key * CHUNK, Vector2i(CHUNK, CHUNK))
	var spots := _clear_spots.filter(func(sp): return area.grow(6).has_point(sp[0]))
	var out := []
	for i in range(area.position.x, mini(area.end.x, N)):
		for j in range(area.position.y, mini(area.end.y, N)):
			var cell := Vector2i(i, j)
			var t := terrain_at(cell)
			if t < 0 or not pdata["terrain"][t][2] or _plot_cells.has(cell) or _blocked_cells.has(cell) or _veg_exclude.has_point(cell):
				continue
			var open := false
			for sp in spots:
				if Vector2(cell).distance_to(Vector2(sp[0])) < sp[1]:
					open = true
			if open:
				continue
			var specs := _tile_flora(cell, pdata["terrain"][t][3], rng) if _tiled else _flora_for(pdata["terrain"][t][3], leaf, rng)
			var rk: int = _solid(i * N + j)
			if rk >= 30:   # scree and boulders round the crags (nothing grows there)
				specs = []
				if rng.randf() < 0.5:
					var stone: Color = pdata.get("rock_color", ROCK_COLOR)
					specs.append(["boulder" if rng.randf() < 0.5 else "rock", stone.lightened(rng.randf_range(-0.12, 0.08)), rng.randf_range(0.7, 1.5)])
			for spec in specs:
				var variant := rng.randi()
				var pos := _cell_pos(cell) + Vector2(rng.randf_range(-48, 48), rng.randf_range(-24, 24))
				if _ground_ok(pos):
					out.append([spec[0], spec[1], spec[2], variant, pos])
	if not _industry.is_empty():
		_industry_in(area, out)
	return out


## Crags' limestone (pdata "rock_color" overrides it).
const ROCK_COLOR := Color(0.8, 0.7, 0.62)   # (warm limestone, pinkish in the sun)


## What grows on a cell: list of [kind, colour, scale].
func _flora_for(kind: String, leaf: Color, rng: RandomNumberGenerator) -> Array:
	var out := []
	var r := rng.randf()
	match kind:
		"forest":
			# Open woodland on the hills (a Greek hillside: trees in clumps,
			# scrub between - room to walk and to see the ground's relief).
			if r < 0.45:
				out.append(["tree", leaf.lightened(rng.randf_range(-0.15, 0.1)), rng.randf_range(0.9, 1.5)])
			if rng.randf() < 0.45:
				out.append(["bush", leaf.darkened(0.15), rng.randf_range(0.8, 1.2)])
			if rng.randf() < 0.12:
				out.append(["rock", Color(0.66, 0.63, 0.56), rng.randf_range(0.6, 1.0)])
			for k in rng.randi_range(1, 3):
				out.append(["tuft", Color(0.3, 0.55, 0.25), rng.randf_range(0.8, 1.2)])
		"grass":
			if r < 0.2:
				out.append(["tree", leaf.lightened(rng.randf_range(-0.1, 0.15)), rng.randf_range(0.8, 1.3)])
			elif r < 0.35:
				out.append(["bush", leaf, rng.randf_range(0.7, 1.1)])
			for k in rng.randi_range(1, 4):
				out.append(["tuft", Color(0.38, 0.62, 0.28).lightened(rng.randf_range(-0.1, 0.15)), rng.randf_range(0.7, 1.2)])
			if rng.randf() < 0.35:
				out.append(["flowers", [Color(1, 0.9, 0.4), Color(1, 0.55, 0.75), Color(0.85, 0.75, 1.0)].pick_random(), 1.0])
		"sand":
			if r < 0.1:
				out.append(["palm", leaf, rng.randf_range(0.9, 1.3)])
			elif r < 0.3:
				out.append(["tuft", Color(0.65, 0.68, 0.4), rng.randf_range(0.6, 0.9)])
			if rng.randf() < 0.2:
				out.append(["pebbles", Color(0.75, 0.68, 0.55), 1.0])
		"regolith", "crater":
			if r < 0.12:
				out.append(["boulder", Color(0.5, 0.5, 0.53).lightened(rng.randf_range(-0.1, 0.15)), rng.randf_range(0.8, 1.6)])
			elif r < 0.25:
				out.append(["rock", Color(0.48, 0.48, 0.5), rng.randf_range(0.6, 1.1)])
			if rng.randf() < 0.45:
				out.append(["pebbles", Color(0.45, 0.45, 0.48), 1.0])
		"ice", "snow":
			if r < 0.12:
				out.append(["crystal", leaf.lightened(rng.randf_range(-0.1, 0.2)), rng.randf_range(0.8, 1.5)])
			elif r < 0.28:
				out.append(["shard", leaf.lightened(0.2), rng.randf_range(0.7, 1.2)])
			if rng.randf() < 0.18:
				out.append(["boulder", Color(0.86, 0.9, 0.96), rng.randf_range(0.6, 1.0)])
	return out


## A piece of scenery. Streamed ones belong to their chunk (freed with it and
## grown again when you come back); others (placed in the level editor or
## from a layout) stay.
func _spawn_prop(kind: String, color: Color, scale_: float, variant: int, pos: Vector2, streamed := false) -> Object:
	var key := _chunk_of(_cell_at(pos))
	if kind in PROPS.FLAT:
		return _spawn_flat_prop(kind, color, scale_, variant, pos, key if streamed else Vector2i(-1, -1))
	var p := PROPS.Prop.new()
	var parent: Node2D = objects
	if streamed:
		p.set_meta("chunk", key)
		if not _chunk_nodes.has(key):
			_chunk_nodes[key] = []
		_chunk_nodes[key].append(p)
		# Each chunk's scenery under its own y-sorted holder (sorted together
		# with everything else): freeing a chunk is one removal from `objects`.
		parent = _chunk_holders.get(key)
		if parent == null:
			parent = Node2D.new()
			parent.y_sort_enabled = true
			objects.add_child(parent)
			_chunk_holders[key] = parent
	p.material = PROPS.atlas_material()
	p.kind = kind
	p.color = color
	p.s = scale_
	p.variant = variant
	p.position = pos
	parent.add_child(p)
	_lift_static(p)
	_props[p] = true
	if kind in ["tree", "palm", "crystal", "boulder"] or TTILES.is_piece(kind):
		_tall_props[p] = true
		var bk := tilemap.local_to_map(p.position) / 4
		if not _prop_buckets.has(bk):
			_prop_buckets[bk] = []
		_prop_buckets[bk].append(p)
	return p


## The buildings' look preset here (Themes, kind "building"), if any: its
## materials go on every wall, floor, roof, column and decor piece.
var _building_skin: Node

func _theme_buildings() -> void:
	var look := Themes.pick("building", Themes.context(planet_id), hash(planet_id))
	if look.is_empty() and EMPIRE_LOOK.has(culture()) and not MinoanTiles.STYLES.has(culture() + "_palace"):
		look = BuildingLook.generate(EMPIRE_LOOK[culture()])   # (the owner's materials - where it has no buildings of its own yet)
	if look.is_empty():
		return
	if _building_skin:
		_building_skin.queue_free()
	_building_skin = BuildingLook.skin(look)
	add_child(_building_skin)
	for b in buildings:
		_dress_building(b)
	if floor_layer:
		BuildingLook.dress([floor_layer], _building_skin, "floors")


## A building in the planet's look preset (if there is one).
func _dress_building(b: BuiltBuilding) -> void:
	if _building_skin == null:
		return
	BuildingLook.dress(b.walls, _building_skin, "walls")
	BuildingLook.dress([b.roof], _building_skin, "roofs")
	BuildingLook.dress(b.columns + b.decor, _building_skin, "decor")
	if b.upper and b.upper.node:
		BuildingLook.dress([b.upper.node], _building_skin, "walls")


## Renders every prop look on this surface into one atlas (SurfaceProps), so
## each prop draws one textured rectangle and they all batch together.
func _build_prop_atlas() -> void:
	var looks := _atlas_looks.duplicate()
	for p in _props:
		if is_instance_valid(p):
			looks.append([p.kind, p.color, p.variant])
	await PROPS.build_atlas(self, looks)
	for p in _props:
		if is_instance_valid(p) and p is Node2D:
			p.queue_redraw()
	for b in _decor_batches.values():
		b.queue_redraw()


## Flat ground cover goes into the chunk's PropBatch (see SurfaceProps.FLAT).
const DECOR_CHUNK := 1024.0

func _spawn_flat_prop(kind: String, color: Color, scale_: float, variant: int, pos: Vector2, chunk := Vector2i(-1, -1)) -> Object:
	if _decor == null:
		_decor = Node2D.new()
		_decor.name = "GroundDecor"
		_decor.z_index = -10   # on the ground, under floors, walls and characters
		add_child(_decor)
		move_child(_decor, objects.get_index())
	# Streamed: one batch per chunk; kept ones: one per DECOR_CHUNK px square.
	var streamed := chunk != Vector2i(-1, -1)
	var key: Variant = chunk if streamed else [Vector2i((pos / DECOR_CHUNK).floor())]
	var batch: Node2D = _decor_batches.get(key)
	if batch == null:
		batch = PROPS.PropBatch.new()
		batch.material = PROPS.atlas_material()
		batch.position = _cell_pos(chunk * CHUNK) if streamed else Vector2((key[0] as Vector2i)) * DECOR_CHUNK
		_decor.add_child(batch)
		_decor_batches[key] = batch
	var d := PROPS.PropData.new()
	d.kind = kind
	d.color = color
	d.s = scale_
	d.variant = variant
	d.position = pos
	d.lift = lift_at(pos)
	d.batch = batch
	d.chunk = chunk
	batch.items.append(d)
	batch.queue_redraw()
	_props[d] = true
	if streamed:
		if not _chunk_data.has(chunk):
			_chunk_data[chunk] = []
		_chunk_data[chunk].append(d)
	return d


func _spawn_npc(pos: Vector2, variant: int, home: Vector2, kind := "") -> Node2D:
	var a: Node2D = PROPS.citizen(kind, variant)
	a.surface = self
	a.home = home
	a.position = pos
	objects.add_child(a)
	npcs.append(a)
	return a


# --- Buildings (assembled from procedural tiles) ------------------------------------

## Minoan floor tiles' sources and how they were made (MinoanTiles.reskin).
var _minoan_floors := {}


## Hot reload (LiveLink): the tile pieces' pictures or the building styles
## changed - every building here gets its textures again (same shape, doors,
## floors and furniture; walls, floors, roofs, crowns, columns and decor
## re-picked from the styles as they are now).
func reskin_buildings() -> int:
	return MinoanTiles.reskin(self, _minoan_floors)


class BuiltBuilding extends RefCounted:
	var rect: Rect2i
	var material := "minoan"
	var light := Color.WHITE
	var title := ""
	var walls: Array = []        # wall tile sprites
	var doors: Array = []        # sliding doors in the doorways
	var segments: Array = []     # blocking wall lines [a, b] (doorways left open)
	var pillars: Array = []      # column positions (block movement)
	var roof: Node2D
	var bounds: Rect2            # ground-level bounding box, for quick tests
	var spec := {}               # blueprint (saved in layouts, used to rebuild)
	var columns: Array = []      # column sprites
	var door_zones: Array = []
	var decor: Array = []        # tile-set decor around Minoan buildings
	var style := "palace"        # Minoan tile set: palace / warehouse / temple
	var upper: RefCounted        # BuildingFloors.Floor: the upper floor and its stairs (or null)
	var furniture: Array = []    # Furniture pieces inside (ground floor)
	var blocks: Array = []       # their footprints (world polygons: block walking)


func _near_door(world: Vector2, extra: float) -> bool:
	for z in _door_zones:
		if world.distance_to(z[0]) < z[1] + extra:
			return true
	return false


## Buildings are at least this many tiles each way.
const MIN_BUILDING := 12


## The height building plots are levelled to: the middle of the walkable
## ground type that covers most of the map.
func _site_height() -> float:
	var counts := {}
	for t in _terrain:
		if pdata["terrain"][t][2]:
			counts[t] = counts.get(t, 0) + 1
	var best := 0
	var best_n := -1
	for t in counts:
		if counts[t] > best_n:
			best = t
			best_n = counts[t]
	var th: Array = pdata["thresholds"]
	var lo: float = th[best - 1] if best > 0 else th[0] - 0.3
	var hi: float = th[best] if best < th.size() else th[-1] + 0.3
	return (lo + hi) * 0.5


func _set_height(c: Vector2i, h: float) -> void:
	var idx := c.x * N + c.y
	_height[idx] = h
	var th: Array = pdata["thresholds"]
	var t := 0
	while t < th.size() and h > th[t]:
		t += 1
	_terrain[idx] = t


## A plot for a building of `size` near `near` (within `radius` cells; < 0:
## anywhere): of the candidates, the one needing the least clearing. Never on
## or next to another building, on the landing pad, or out on the map's rim.
func _find_clear_site(size: Vector2i, near: Vector2i, radius: int) -> Rect2i:
	var center := Vector2i(N / 2, N / 2)
	var best := Rect2i()
	var best_cost := INF
	for attempt in 90:
		var pos: Vector2i
		if radius < 0:
			pos = Vector2i(_rng.randi_range(6, N - 6 - size.x), _rng.randi_range(6, N - 6 - size.y))
		else:
			pos = near + Vector2i(_rng.randi_range(-radius, radius), _rng.randi_range(-radius, radius)) - size / 2
		var r := Rect2i(pos, size)
		var g := r.grow(2)
		if g.position.x < 5 or g.position.y < 5 or g.end.x > N - 5 or g.end.y > N - 5:
			continue
		if g.grow(3).has_point(center) or g.grow(3).has_point(center + Vector2i(1, 1)):
			continue   # the landing pad (and where you step out)
		var ok := true
		for c in [g.position, Vector2i(g.end.x, g.position.y), g.end, Vector2i(g.position.x, g.end.y)]:
			if Vector2(c).distance_to(Vector2(center)) > N * 0.5 * 0.82:
				ok = false   # (the rim drifts down into sea / crevasses)
		for other in buildings:
			if other.rect.grow(4).intersects(r):
				ok = false
		for p in _plans:
			if _plan_rect(p).grow(4).intersects(r):
				ok = false
		if not ok:
			continue
		var cost := 0.0
		for i in range(g.position.x, g.end.x, 2):
			for j in range(g.position.y, g.end.y, 2):
				if not walkable_cell(Vector2i(i, j)):
					cost += 4.0
				cost += absf(_height[i * N + j] - _site_h) * 6.0   # (low ramps: valleys at the site height)
		cost += Vector2(r.get_center()).distance_to(Vector2(near)) * 0.15
		if cost < best_cost:
			best = r
			best_cost = cost
	return best


## (worker thread) Ground within `r` tiles of `c` at the site height, easing
## back into the land over `ease` more.
func _level_disc(c: Vector2i, r: float, ease: float) -> void:
	var R := ceili(r + ease)
	for dx in range(-R, R + 1):
		for dy in range(-R, R + 1):
			var q := c + Vector2i(dx, dy)
			if q.x < 0 or q.y < 0 or q.x >= N or q.y >= N:
				continue
			var d := Vector2(dx, dy).length()
			if d > r + ease:
				continue
			var k := 1.0 - smoothstep(r, r + ease, d)
			_set_height(q, lerpf(_height[q.x * N + q.y], _site_h, k))
			_ramp[q.x * N + q.y] = 1.0


## Tiles over which a levelled plot ramps back into the land round it.
const PLOT_EASE := 10

## Levels a building plot: the rectangle and two tiles around it flat at the
## site height (water, crevasses, rock and slopes gone), easing into the
## land around over two more tiles. Call _refresh_terrain() afterwards.
func _clear_site(r: Rect2i) -> void:
	if _site_h == 0.0:
		_site_h = _site_height()
	var h := _site_h
	var g := r.grow(2 + PLOT_EASE)
	for i in range(maxi(g.position.x, 0), mini(g.end.x, N)):
		for j in range(maxi(g.position.y, 0), mini(g.end.y, N)):
			var c := Vector2i(i, j)
			var d := maxi(maxi(r.position.x - i, i - (r.end.x - 1)), maxi(r.position.y - j, j - (r.end.y - 1)))
			if d <= 4:
				_rock[i * N + j] = 0
			_ramp[i * N + j] = 1.0   # (the plot's ramp: slopes into the ledges round it, no cliffs)
			if d <= 2:
				_set_height(c, h)
			else:   # (a ramp into the hills round it: the elevation follows)
				_set_height(c, lerpf(_height[i * N + j], h, 1.0 - smoothstep(2.0, 2.0 + PLOT_EASE, d)))


## Builds floors (TileMapLayer), wall tiles, doorways, inner walls and a roof.
## doors: [[cell, side], ...]; inner: [[axis "i"/"j", k, from, to, door_at], ...]
func _build_building(rect: Rect2i, material: String, doors: Array, inner: Array, mosaic := Rect2i(), overrides := {}, style := "palace") -> BuiltBuilding:
	var b := BuiltBuilding.new()
	b.style = style
	b.spec = {"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "material": material,
		"doors": doors.map(func(d): return [d[0].x, d[0].y, d[1]]), "inner": inner,
		"mosaic": [mosaic.position.x, mosaic.position.y, mosaic.size.x, mosaic.size.y] if mosaic.size != Vector2i.ZERO else [],
		"overrides": overrides, "columns": [], "style": style}
	b.rect = rect
	b.material = material
	b.light = pdata["light"]
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x - 1
	var y1 := rect.end.y - 1
	for i in range(x0, x1 + 1):
		for j in range(y0, y1 + 1):
			var cell := Vector2i(i, j)
			var fk := ("mosaic" if mosaic.has_point(cell) else "minoan") + ":" + style
			_set_floor(cell, fk, (i * 7 + j * 3) % 3)
			var sides := []
			if i == x0: sides.append("nw")
			if j == y0: sides.append("ne")
			if i == x1: sides.append("se")
			if j == y1: sides.append("sw")
			for side in sides:
				var kind := "plain"
				if [cell, side] in doors:
					kind = "door"
				elif (i + j) % 2 == 0:
					kind = "window"
				_add_wall(b, cell, side, overrides.get(_edge_key(cell, side), kind))
	for w in inner:
		for n in range(w[2], w[3] + 1):
			var cell := Vector2i(w[1], n) if w[0] == "i" else Vector2i(n, w[1])
			var side: String = "nw" if w[0] == "i" else "ne"
			_add_wall(b, cell, side, overrides.get(_edge_key(cell, side), "door" if n == w[4] else "plain"))
	_add_roof(b)
	if material == "minoan" and MinoanTiles.available():
		_minoan_decor(b)
	var bounds := Rect2(b.segments[0][0], Vector2.ZERO)
	for seg in b.segments:
		bounds = bounds.expand(seg[0]).expand(seg[1])
	b.bounds = bounds.grow(16)
	for i in range(x0 - 1, x1 + 2):
		for j in range(y0 - 1, y1 + 2):
			_blocked_cells[Vector2i(i, j)] = true
	buildings.append(b)
	_bgrid_ok = false
	return b


func _set_floor(cell: Vector2i, kind: String, variant: int) -> void:
	if floor_layer == null:
		var ts := TileSet.new()
		ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
		ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
		ts.tile_size = TILE
		floor_layer = TileMapLayer.new()
		floor_layer.tile_set = ts
		floor_layer.z_index = -9
		add_child(floor_layer)
	var key := "%s%d" % [kind, variant]
	if not _floor_sources.has(key):
		var src := TileSetAtlasSource.new()
		var kp: PackedStringArray = kind.split(":")
		if kp[0] in ["minoan", "mosaic"] and MinoanTiles.available():
			TextureAtlas.set_source_texture(src, MinoanTiles.floor_tile(kp[0], variant, kp[1] if kp.size() > 1 else "palace"))
			_minoan_floors[src] = [kp[0], variant, kp[1] if kp.size() > 1 else "palace"]
		else:
			src.texture = SurfaceTiles.floor_tile(kind, pdata["building_color"], pdata["light"], variant)
		src.texture_region_size = TILE
		src.create_tile(Vector2i.ZERO)
		_floor_sources[key] = floor_layer.tile_set.add_source(src)
	floor_layer.set_cell(cell, _floor_sources[key], Vector2i.ZERO)


## One wall tile on a cell edge. Back walls (nw/ne) sort behind the room,
## front walls (se/sw) in front of it - those fade when you're behind them.
func _add_wall(b: BuiltBuilding, cell: Vector2i, side: String, kind: String) -> void:
	var c := _cell_pos(cell)
	var h := SurfaceTiles.WALL_H
	var start: Vector2
	var dir: Vector2
	var orient := "x"
	match side:
		"ne":
			start = c + Vector2(0, -32); dir = Vector2(64, 32)
		"sw":
			start = c + Vector2(-64, 0); dir = Vector2(64, 32)
		"nw":
			start = c + Vector2(-64, 0); dir = Vector2(64, -32); orient = "y"
		"se":
			start = c + Vector2(0, 32); dir = Vector2(64, -32); orient = "y"
	var front := side == "se" or side == "sw"
	var s := _wall_sprite(b, start, orient, kind, _variant(cell, side))
	var mid := start + dir * 0.5
	s.position = Vector2(mid.x, c.y + (40.0 if front else -40.0))
	var top_left := start - Vector2(0, h) if orient == "x" else start - Vector2(0, h + 32)
	s.offset = (top_left - s.position) / s.scale.x
	if front:
		s.set_meta("front_of", b)
	_slice_wall(s, start, dir, front)
	s.set_meta("edge", _edge_key(cell, side))
	s.set_meta("kind", kind)
	s.set_meta("seg", [start, start + dir])
	objects.add_child(s)
	b.walls.append(s)
	_occluders.append(s)
	if kind == "door":
		# Keep the approach to the doorway clear on both sides.
		var normal := Vector2(-dir.y, dir.x).normalized() * 70.0
		for z in [[mid + normal, 95.0], [mid - normal, 95.0]]:
			_door_zones.append(z)
			b.door_zones.append(z)
		b.segments.append([start, start + dir * SurfaceTiles.DOOR.x])
		b.segments.append([start + dir * SurfaceTiles.DOOR.y, start + dir])
		# A sliding door in the opening (opens as you approach).
		var door := Node2D.new()
		door.set_script(preload("res://scripts/sliding_door.gd"))
		door.position = Vector2(mid.x, mid.y + (WALL_SORT + 0.5 if front else -WALL_SORT + 0.5))   # just after its wall
		door.start = start
		door.dir = dir
		door.height = SurfaceTiles.WALL_H * (1.0 - 0.36)
		door.wall = s
		door.surface = self
		if b.material == "minoan":
			door.panel = Color(0.62, 0.42, 0.22)    # bronze
			door.trim = Color(0.98, 0.8, 0.35)
			door.glow = Color(1.0, 0.75, 0.35)
		else:
			door.panel = (pdata["building_color"] as Color).lerp(Color(0.6, 0.65, 0.72), 0.5)
			door.trim = pdata["light"]
			door.glow = pdata["light"]
		objects.add_child(door)
		b.doors.append(door)
	else:
		b.segments.append([start, start + dir])


## Depth sorting of a wall: a wall runs diagonally, so no single height sorts
## it right against people walking past - someone in front of one end would
## be drawn behind it. Each wall is drawn as WALL_SLICES vertical strips, each
## sorted at the wall's own ground line where it stands (front walls a little
## below it, back walls a little above): whoever is in front of the line is
## drawn in front of the wall, whoever is behind it is hidden.
const WALL_SLICES := 4
const WALL_SORT := 3.0


func _slice_wall(s: Sprite2D, start: Vector2, dir: Vector2, front: bool) -> void:
	var tex := s.texture
	if tex == null:
		return
	var k := s.scale.x
	var w := tex.get_width() / float(WALL_SLICES)
	var top_left := s.position + s.offset * k
	s.y_sort_enabled = true
	s.self_modulate.a = 0.0    # the strips draw it (fading still follows s.modulate)
	for i in WALL_SLICES:
		var piece := Sprite2D.new()
		piece.texture = tex
		piece.centered = false
		piece.region_enabled = true
		piece.region_rect = Rect2(i * w, 0, w, tex.get_height())
		var ground := start + dir * ((i + 0.5) / WALL_SLICES)
		var at := Vector2(ground.x, ground.y + (WALL_SORT if front else -WALL_SORT))
		# In s's (scaled) space: its children inherit its scale.
		piece.position = (at - s.position) / k
		piece.offset = (top_left + Vector2(i * w * k, 0) - at) / k
		s.add_child(piece)


## A wall face sprite: Minoan buildings use the traced tile set (MinoanTiles),
## at 2x resolution shown at half scale.
func _wall_sprite(b: BuiltBuilding, _start: Vector2, orient: String, kind: String, variant: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	if b.material == "minoan" and MinoanTiles.available():
		s.texture = MinoanTiles.wall(orient, kind, variant, b.style)
		s.scale = Vector2.ONE / MinoanTiles.RES
		MinoanTiles.tag(s, ["wall", orient, kind, variant, b.style])
	else:
		s.texture = SurfaceTiles.wall(b.material, orient, kind, pdata["building_color"], pdata["light"])
	return s


## A stable per-edge variety pick (frescoes, windows, beams).
func _variant(cell: Vector2i, side: String) -> int:
	return absi(hash(_edge_key(cell, side)))


func _add_roof(b: BuiltBuilding) -> void:
	var roof := Node2D.new()
	roof.position = _cell_pos(b.rect.end - Vector2i.ONE) + Vector2(0, 54)  # sorts after the walls
	objects.add_child(roof)
	var minoan := b.material == "minoan" and MinoanTiles.available()
	for i in range(b.rect.position.x, b.rect.end.x):
		for j in range(b.rect.position.y, b.rect.end.y):
			var sp := Sprite2D.new()
			sp.texture = MinoanTiles.roof_tile((i + j) % 2, b.style) if minoan else SurfaceTiles.roof_tile(b.material, pdata["building_color"], pdata["light"], (i + j) % 2)
			if minoan:
				MinoanTiles.tag(sp, ["roof", (i + j) % 2, b.style])
			sp.position = _cell_pos(Vector2i(i, j)) - Vector2(0, SurfaceTiles.WALL_H) - roof.position
			roof.add_child(sp)
	b.roof = roof
	if minoan:
		_minoan_crown(b, roof)


## The Minoan palace silhouette on the roof (it fades with the roof): an upper
## storey on bigger buildings, roof caps on the corners, antennas and the
## golden bull's horns on top - as in the tile set's layer diagram.
func _minoan_crown(b: BuiltBuilding, roof: Node2D) -> void:
	var st := MinoanTiles.style(b.style)
	var r := b.rect
	var lift := float(SurfaceTiles.WALL_H)
	var top := r
	if r.size.x >= 4 and r.size.y >= 4:
		var inner := Rect2i(r.position + Vector2i.ONE, r.size - Vector2i(2, 2))
		top = inner
		# Upper walls: back walls, the upper roof, then front walls.
		var x0 := inner.position.x
		var y0 := inner.position.y
		var x1 := inner.end.x - 1
		var y1 := inner.end.y - 1
		for pass_ in ["back", "roof", "front"]:
			if pass_ == "roof":
				for i in range(x0, x1 + 1):
					for j in range(y0, y1 + 1):
						var sp := Sprite2D.new()
						sp.texture = MinoanTiles.roof_tile((i + j + 1) % 2, b.style)
						MinoanTiles.tag(sp, ["roof", (i + j + 1) % 2, b.style])
						sp.position = _cell_pos(Vector2i(i, j)) - Vector2(0, lift * 2.0) - roof.position
						roof.add_child(sp)
				continue
			for i in range(x0, x1 + 1):
				for j in range(y0, y1 + 1):
					var sides := []
					if pass_ == "back":
						if i == x0: sides.append("nw")
						if j == y0: sides.append("ne")
					else:
						if i == x1: sides.append("se")
						if j == y1: sides.append("sw")
					for side in sides:
						roof.add_child(_upper_wall(b, Vector2i(i, j), side, lift, roof.position))
	# Roof caps on the corners of the top, antennas at the back, horns in the middle.
	var h := lift * (2.0 if top != r else 1.0)
	var corners := [Vector2i(top.position.x, top.end.y - 1), Vector2i(top.end.x - 1, top.position.y), Vector2i(top.end.x - 1, top.end.y - 1)]
	for k in corners.size():
		var cp := _cell_pos(corners[k]) - Vector2(0, h) - roof.position
		roof.add_child(MinoanTiles.tag(MinoanTiles.sprite(st["caps"][k], cp + Vector2(0, 26)), ["piece", b.style, "caps", k, 0.0]))
	roof.add_child(MinoanTiles.tag(MinoanTiles.sprite(st["antenna"], _cell_pos(top.position) - Vector2(0, h) - roof.position + Vector2(0, 20)),
		["piece", b.style, "antenna", 0, 0.0]))
	var centre := (_cell_pos(top.position) + _cell_pos(top.end - Vector2i.ONE)) / 2.0 - Vector2(0, h) - roof.position
	roof.add_child(MinoanTiles.tag(MinoanTiles.sprite(st["dome"], centre + Vector2(0, 30)), ["piece", b.style, "dome", 0, 0.0]))
	var horns_h := 150.0 if b.style == "palace" else 110.0
	roof.add_child(MinoanTiles.tag(MinoanTiles.sprite(st["horns"], centre + Vector2(0, -8), horns_h), ["piece", b.style, "horns", 0, horns_h]))


## A wall of the upper storey (drawn on the roof node, lifted one storey).
func _upper_wall(b: BuiltBuilding, cell: Vector2i, side: String, lift: float, origin: Vector2) -> Sprite2D:
	var c := _cell_pos(cell)
	var h := SurfaceTiles.WALL_H
	var start: Vector2
	var orient := "x"
	match side:
		"ne": start = c + Vector2(0, -32)
		"sw": start = c + Vector2(-64, 0)
		"nw": start = c + Vector2(-64, 0); orient = "y"
		"se": start = c + Vector2(0, 32); orient = "y"
	var kind := "window" if _variant(cell, side) % 3 == 0 else "plain"
	var s := _wall_sprite(b, start, orient, kind, _variant(cell, side) / 7)
	var top_left := (start - Vector2(0, h) if orient == "x" else start - Vector2(0, h + 32)) - Vector2(0, lift)
	s.position = top_left - origin
	s.offset = Vector2.ZERO
	return s


## Urns, trees, flowers, crates, a banner and the hologram around a Minoan
## building - on its outer side, kept off the door approaches.
func _minoan_decor(b: BuiltBuilding) -> void:
	var r := b.rect
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(b.spec)
	var st := MinoanTiles.style(b.style)
	var picks: Array = st["decor"]
	var spots := []
	for i in range(r.position.x, r.end.x):   # along the front (south-west) wall
		spots.append(_cell_pos(Vector2i(i, r.end.y)) + Vector2(-20, -20))
	for j in range(r.position.y, r.end.y):   # along the front (south-east) wall
		spots.append(_cell_pos(Vector2i(r.end.x, j)) + Vector2(20, -20))
	for k in spots.size():
		var p: Vector2 = spots[k]
		if _near_door(p, 40.0) or not walkable_at(p) or rng.randf() < 0.45:
			continue
		var roll := rng.randi()
		var s := MinoanTiles.tag(MinoanTiles.sprite(picks[roll % picks.size()], p), ["decor", b.style, roll]) as Sprite2D
		objects.add_child(s)
		_occluders.append(s)
		b.decor.append(s)
	# The hologram beacon and a banner by the first door.
	for z in b.door_zones:
		var p: Vector2 = z[0]
		if walkable_at(p):
			var holo := MinoanTiles.tag(MinoanTiles.sprite(st["entrance"][0], p + Vector2(70, 10)), ["piece", b.style, "entrance", 0, 0.0]) as Sprite2D
			objects.add_child(holo)
			b.decor.append(holo)
			var ban := MinoanTiles.tag(MinoanTiles.sprite(st["entrance"][1], p + Vector2(-70, 4)), ["piece", b.style, "entrance", 1, 0.0]) as Sprite2D
			objects.add_child(ban)
			_occluders.append(ban)
			b.decor.append(ban)
			break


func _add_column(b: BuiltBuilding, cell: Vector2i) -> void:
	var s: Sprite2D
	if b.material == "minoan" and MinoanTiles.available():
		s = MinoanTiles.sprite(MinoanTiles.style(b.style)["column"], _cell_pos(cell) + Vector2(0, 4), SurfaceTiles.WALL_H + 16.0)
		MinoanTiles.tag(s, ["piece", b.style, "column", 0, SurfaceTiles.WALL_H + 16.0])
	else:
		s = Sprite2D.new()
		s.texture = SurfaceTiles.column()
		s.centered = false
		s.position = _cell_pos(cell)
		s.offset = Vector2(-s.texture.get_width() / 2.0, -s.texture.get_height() + 4)
	objects.add_child(s)
	_occluders.append(s)
	b.pillars.append(s.position)
	b.columns.append(s)
	b.spec["columns"].append([cell.x, cell.y])


## Keep the player visible: roofs vanish when you're inside, and walls,
## columns, roofs and tall scenery in front of you turn see-through.
func _update_occlusion(delta: float) -> void:
	var p := pilot.position
	var chest := p + Vector2(0, -44)
	var cell := tilemap.local_to_map(p)
	var inside: BuiltBuilding = null
	for b in buildings:
		if b.rect.has_point(cell):
			inside = b
	var k := delta * 6.0
	for o in _occluders:
		if absf(o.position.x - p.x) >= 220.0 and o.modulate.a == 1.0 and (inside == null or level != 0 or not o.has_meta("front_of") or o.get_meta("front_of") != inside):
			continue   # (far to the side, not faded, not the room you're in: nothing to do - most of them)
		var target := 1.0
		if o.position.y > p.y and absf(o.position.x - p.x) < 220.0:
			var r := Rect2(o.position + o.offset * o.scale, o.texture.get_size() * o.scale).grow(8)
			if r.has_point(chest) or r.has_point(p + Vector2(0, -8)):
				target = 0.22
		if level == 0 and inside != null and o.has_meta("front_of") and o.get_meta("front_of") == inside:
			target = minf(target, 0.35)  # see into the room you're in
		o.modulate.a = move_toward(o.modulate.a, target, k)
	for b in buildings:
		var target := 1.0
		if b == inside:
			target = 0.0
		elif p.y < b.roof.position.y:
			var top: Rect2 = b.bounds
			top.position.y -= SurfaceTiles.WALL_H
			if top.has_point(chest):
				target = 0.25
		b.roof.modulate.a = move_toward(b.roof.modulate.a, target, k)
	# Upstairs: the upper room's front walls fade while you're in the room.
	if level == 1 and level_b.upper != null:
		var in_room: bool = level_b.upper.room.has_point(cell)
		for w in level_b.upper.front_walls:
			w.modulate.a = move_toward(w.modulate.a, 0.35 if in_room else 1.0, k)
	# Your landed ship (about 280 x 150 px) fades when you walk behind it.
	var lt := 1.0
	if p.y < lander.position.y and absf(p.x - lander.position.x) < 150.0 and p.y > lander.position.y - 170.0:
		lt = 0.3
	lander.modulate.a = move_toward(lander.modulate.a, lt, k)
	# Tall scenery: only props near you (by bucket) and ones still fading back.
	var near: Array = []
	var bc := cell / 4
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			near.append_array(_prop_buckets.get(bc + Vector2i(dx, dy), []))
	for o in _faded:
		if not near.has(o):
			near.append(o)
	var still: Array = []
	for o in near:
		if not is_instance_valid(o):
			continue
		var target := 1.0
		if o.position.y > p.y and absf(o.position.x - p.x) < 90.0 * o.s and p.y > o.position.y - 110.0 * o.s:
			target = 0.3
		if o.modulate.a != target:
			o.modulate.a = move_toward(o.modulate.a, target, k)
		if o.modulate.a < 1.0:
			still.append(o)
	_faded = still


# --- Layouts & level editor -----------------------------------------------------------

func _edge_key(cell: Vector2i, side: String) -> String:
	return "%d,%d,%s" % [cell.x, cell.y, side]


func _layout_path() -> String:
	return "res://data/planets/%s.json" % planet_id


## A layout saved for a smaller map sits in the middle of this one:
## cell / world offsets for its contents (zero for a full-size layout).
var _layout_off := 0
var _layout_rect := Rect2i()


func _apply_layout_heights() -> void:
	var h: Array = _layout.get("heights", [])
	var old_n := roundi(sqrt(h.size()))
	if old_n * old_n != h.size() or old_n > N or old_n == 0:
		return
	_layout_off = (N - old_n) / 2
	_layout_rect = Rect2i(_layout_off, _layout_off, old_n, old_n)
	var thresholds: Array = pdata["thresholds"]
	for i in old_n:
		for j in old_n:
			var k := (i + _layout_off) * N + (j + _layout_off)
			var v := float(h[i * old_n + j]) + LAND_BIAS
			# Blend the outermost cells into the generated terrain around it.
			var edge := mini(mini(i, j), mini(old_n - 1 - i, old_n - 1 - j))
			if edge < 3 and old_n < N:
				v = lerpf(_height[k], v, (edge + 1) / 4.0)
			_height[k] = v
	for k in N * N:
		var t := 0
		while t < thresholds.size() and _height[k] > thresholds[t]:
			t += 1
		_terrain[k] = t


## World offset of the embedded layout.
func _layout_shift() -> Vector2:
	return _cell_pos(Vector2i(_layout_off, _layout_off)) - _cell_pos(Vector2i.ZERO)


## A building blueprint moved by the layout offset.
func _shift_spec(spec: Dictionary) -> Dictionary:
	if _layout_off == 0:
		return spec
	var o := _layout_off
	var s := spec.duplicate(true)
	var r: Array = s["rect"]
	s["rect"] = [r[0] + o, r[1] + o, r[2], r[3]]
	s["doors"] = s.get("doors", []).map(func(d): return [d[0] + o, d[1] + o, d[2]])
	s["inner"] = s.get("inner", []).map(func(w): return [w[0], w[1] + o, w[2] + o, w[3] + o, w[4] + o])
	var m: Array = s.get("mosaic", [])
	if m.size() == 4:
		s["mosaic"] = [m[0] + o, m[1] + o, m[2], m[3]]
	s["columns"] = s.get("columns", []).map(func(c): return [c[0] + o, c[1] + o])
	var ov := {}
	for key in s.get("overrides", {}):
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() == 3:
			ov["%d,%d,%s" % [parts[0].to_int() + o, parts[1].to_int() + o, parts[2]]] = s["overrides"][key]
		else:
			ov[key] = s["overrides"][key]
	s["overrides"] = ov
	return s


func _place_from_layout() -> void:
	var w := _layout_shift()
	if _layout_off == 0:
		# A full-size layout: its buildings and citizens stream in like a
		# generated planet's (scenery grows around them; hand-placed props stay).
		for spec in _layout.get("buildings", []):
			_add_plan(spec)
		for a in _layout.get("npcs", []):
			_npc_plans.append({"pos": Vector2(a[0], a[1]), "variant": int(a[2]), "home": Vector2(a[0], a[1]), "spawned": false,
				"kind": str(a[3]) if a.size() > 3 else ""})
		await _stream_plans(true)
	else:
		await _place_small_layout(w)
	var props: Array = _layout.get("props", [])
	for k in props.size():
		var p: Array = props[k]
		if (k & 63) == 0 and _yield_due():
			await _breathe(lerpf(0.29, 0.34, float(k) / props.size()), "Planting trees and scenery")
		_spawn_prop(p[0], Color(p[4]), float(p[3]), int(p[5]), Vector2(p[1], p[2]) + w)


## An older, smaller layout in the middle of the planet: built at once.
func _place_small_layout(w: Vector2) -> void:
	for spec in _layout.get("buildings", []):
		if _yield_due():
			await _breathe(0.28, "Raising the Minoan buildings")
		_build_from_spec(_shift_spec(spec))
	await _breathe(0.29, "Gathering the citizens")
	for a in _layout.get("npcs", _layout.get("aliens", [])):   # (older layouts: "aliens")
		_spawn_npc(Vector2(a[0], a[1]) + w, int(a[2]), Vector2(a[0], a[1]) + w)


## A dividing wall for a one-room house (two rooms, a doorway in the middle
## of the wall), placed clear of the outer doors' tile columns; [] if the
## house is too small.
func _divider(r: Rect2i, doors: Array) -> Array:
	if r.size.x < 4:
		return []
	var door_x: Array = doors.map(func(d): return (d[0] as Vector2i).x)
	var best := -1
	var best_w := -1
	for x in range(r.position.x + 1, r.end.x):
		if x in door_x:
			continue
		var w := mini(x - r.position.x, r.end.x - x)
		if w > best_w:
			best_w = w
			best = x
	if best < 0 or best_w < 2:   # both rooms at least two tiles wide
		return []
	return [["i", best, r.position.y, r.end.y - 1, r.position.y + r.size.y / 2]]


func _build_from_spec(spec: Dictionary) -> BuiltBuilding:
	var b := _build_shell(spec)
	BuildingFloors.add(self, b)
	_furnish(b)
	_furnish_upper(b)
	return b


## A building's walls, floors and columns (the first step of raising one).
func _build_shell(spec: Dictionary) -> BuiltBuilding:
	var r: Array = spec["rect"]
	var doors: Array = spec.get("doors", []).map(func(d): return [Vector2i(d[0], d[1]), d[2]])
	var m: Array = spec.get("mosaic", [])
	var inner: Array = spec.get("inner", [])
	if inner.is_empty():   # saved one-room houses get a second room
		inner = _divider(Rect2i(r[0], r[1], r[2], r[3]), doors)
	var b := _build_building(Rect2i(r[0], r[1], r[2], r[3]), spec.get("material", "minoan"), doors,
		inner, Rect2i(m[0], m[1], m[2], m[3]) if m.size() == 4 else Rect2i(), spec.get("overrides", {}).duplicate(),
		spec.get("style", "palace"))
	b.title = spec.get("title", "")
	for c in spec.get("columns", []):
		_add_column(b, Vector2i(c[0], c[1]))
	return b


## Raising a building as you walk near it, a step a frame (_raise_step): its
## shell; its stairs and upper floor; its furniture; upstairs' - all in one
## frame was a 25-45 ms stall each time a building came into reach.
var _raising := {}

func _raise_step() -> bool:
	if _raising.is_empty():
		return false
	var p: Dictionary = _raising["plan"]
	var step: int = _raising["step"]
	_raising["step"] = step + 1
	match step:
		0:
			_raising["b"] = _build_shell(p["spec"])
		1:
			BuildingFloors.add(self, _raising["b"])
		2:
			_furnish(_raising["b"])
		_:
			var b: BuiltBuilding = _raising["b"]
			_furnish_upper(b)
			p["built"] = b
			_dress_building(b)
			if _nav_window().intersects(_plan_rect(p).grow(2)):
				_nav_dirty = true
			_raising = {}
	return true


const MAX_EACH_KIND := 2
## Each empire's own pieces among its buildings' furniture (Furniture.KINDS,
## drawn in code): by the empire that holds this planet's system.
const EMPIRE_FURNITURE := {
	"athens": {"palace": ["owl", "krater", "krater"], "temple": ["owl", "krater"], "warehouse": ["krater"]},
	"sparta": {"palace": ["shield_rack"], "temple": ["shield_rack"], "warehouse": ["shield_rack", "shield_rack"]},
	"mycenae": {"palace": ["lion_relief"], "temple": ["lion_relief"], "warehouse": ["lion_relief"]},
	"ionia": {"palace": ["ionic_column", "star_globe"], "temple": ["ionic_column", "star_globe"], "warehouse": ["star_globe"]},
	"cyclades": {"palace": ["idol", "idol"], "temple": ["idol", "idol"], "warehouse": ["idol"]},
}
## Each empire's building look (BuildingLook.TEMPLATES) where no theme
## preset says otherwise; the Minoans' as painted.
const EMPIRE_LOOK := {"athens": "athenian", "sparta": "spartan", "mycenae": "mycenaean", "ionia": "ionian", "cyclades": "cycladic"}


func _culture_name() -> String:
	return str(Galaxy.EMPIRES.get(culture(), {}).get("short", "Minoan")) if EMPIRE_LOOK.has(culture()) else "Minoan"


## The culture this planet's buildings follow: the empire holding its system.
## The holding empire's tile pieces' prefix (MinoanTiles: "ath", "spa"...).
func _culture_prefix() -> String:
	return {"athens": "ath", "sparta": "spa", "mycenae": "myc", "ionia": "ion", "cyclades": "cyc"}.get(culture(), "palace")


func culture() -> String:
	return Galaxy.owner_of(Galaxy.current_system)


## The Minoans' own sacred pieces: not in other peoples' buildings.
const MINOAN_ONLY := ["goddess", "labrys", "rhyton", "rug_dolphins", "lustral_basin"]


func _furniture_for(style: String) -> Array:
	var base: Array = FURNITURE.get(style, FURNITURE["palace"])
	if EMPIRE_FURNITURE.has(culture()):
		base = base.filter(func(k): return not k in MINOAN_ONLY)
	return base + EMPIRE_FURNITURE.get(culture(), {}).get(style, [])
## What furnishes each kind of building (picked at random along the walls).
## (Furniture.KINDS: the painted pieces of art/furniture/.)
const FURNITURE := {
	"palace": ["table", "chair", "throne", "bench", "couch", "bed", "closet", "bookshelf", "chest", "pithos",
		"round_table", "fruit", "basin", "cushions", "lilies", "olive", "rug", "rug_dolphins", "loom", "lamp", "chair", "table"],
	"warehouse": ["locker", "crates", "vault", "chest", "pithos", "workbench", "console", "power_core", "weapon_rack",
		"alcove", "desk", "med_pod", "holo_table", "shards", "crates", "locker"],
	"temple": ["bookshelf", "chest", "pithos", "vault", "altar", "goddess", "rhyton", "labrys", "offering_table",
		"incense", "lamp", "lustral_basin", "tablets", "cauldron", "hearth", "rug"],
}


## Furniture along the rooms' back walls (Furniture): never in a doorway, on
## the stairs or by a column, a gap between pieces, at least one container.
## The same building always gets the same furniture (seeded by its blueprint);
## containers you've opened stay open (state "planets" -> "opened").
func _furnish(b: BuiltBuilding) -> void:
	var r := b.rect
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(b.spec) + 5
	var avoid := {}
	var near := func(c: Vector2i) -> void:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				avoid[c + Vector2i(dx, dy)] = true
	for d in b.spec.get("doors", []):
		near.call(Vector2i(d[0], d[1]))
	var walls := {}                   # cell -> ["nw" / "ne", ...] (back walls)
	for i in range(r.position.x, r.end.x):
		for j in range(r.position.y, r.end.y):
			var sides := []
			if i == r.position.x:
				sides.append("nw")
			if j == r.position.y:
				sides.append("ne")
			if not sides.is_empty():
				walls[Vector2i(i, j)] = sides
	for w in b.spec.get("inner", []):
		for n in range(w[2], w[3] + 1):
			var c := Vector2i(w[1], n) if w[0] == "i" else Vector2i(n, w[1])
			if n == w[4]:   # its doorway: both sides kept clear
				near.call(c)
				near.call(c - (Vector2i(1, 0) if w[0] == "i" else Vector2i(0, 1)))
				continue
			var list: Array = walls.get(c, [])
			list.append("nw" if w[0] == "i" else "ne")
			walls[c] = list
	for c in b.spec.get("columns", []):
		near.call(Vector2i(c[0], c[1]))
	if b.upper != null:
		for c in [b.upper.stair_a, b.upper.stair_0, b.upper.stair_1, b.upper.landing]:
			near.call(c)
	var cells := walls.keys()
	cells.sort()
	for k in range(cells.size() - 1, 0, -1):   # shuffled (seeded)
		var m := rng.randi() % (k + 1)
		var t: Vector2i = cells[k]
		cells[k] = cells[m]
		cells[m] = t
	var opened: Dictionary = state["planets"].get(planet_id, {}).get("opened", {})
	var picks: Array = _furniture_for(b.style)
	var used := {}
	var limit := maxi(4, r.size.x * r.size.y / 9)
	var count := {}                   # kind -> pieces (at most MAX_EACH_KIND)
	var place := func(c: Vector2i, kind: String) -> Furniture:
		var placed := _place_piece(b, kind, walls[c][rng.randi() % walls[c].size()], c, opened)
		if placed:
			count[kind] = count.get(kind, 0) + 1
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					used[c + Vector2i(dx, dy)] = true
		return placed
	for c in cells:
		if b.furniture.size() >= limit:
			break
		if avoid.has(c) or used.has(c) or rng.randf() < 0.35:
			continue
		var kind: String = picks[rng.randi() % picks.size()]
		if count.get(kind, 0) >= MAX_EACH_KIND:
			continue
		place.call(c, kind)
	# At least one container in every building.
	if not b.furniture.any(func(f): return f.is_container()):
		for c in cells:
			if not avoid.has(c) and not used.has(c) and place.call(c, "chest") != null:
				break
	if not b.furniture.any(func(f): return f.is_container()):
		# (every spot by the walls taken: a chest instead of one of the pieces)
		for old in b.furniture.duplicate():
			if not walls.has(old.cell):
				continue
			b.furniture.erase(old)
			old.queue_free()
			if _place_piece(b, "chest", walls[old.cell][0], old.cell, opened) != null:
				break


## One piece, if it fits: its front and middle on open floor, clear of the
## doors and columns. Null if not.
func _place_piece(b: BuiltBuilding, kind: String, wall: String, cell: Vector2i, opened: Dictionary) -> Furniture:
	var f: Furniture = Furniture.new().setup(kind, wall, cell, _cell_pos(cell), b.style)
	var probe := [f.position, (f.footprint[1] + f.footprint[2]) * 0.5 if wall == "nw" else (f.footprint[2] + f.footprint[3]) * 0.5]
	if f.is_container():
		probe.append(f.approach())
	for p in probe:
		if not walkable_at(p) or _near_door(p, 50.0):
			f.free()
			return null
	for pp in b.pillars:
		if f.position.distance_to(pp) < 60.0:
			f.free()
			return null
	if f.is_container() and opened.has(f.key):
		f.opened = true
		f._update_title()
	objects.add_child(f)
	b.furniture.append(f)
	if not f.is_flat():
		b.blocks.append(f.footprint)
	return f


## The upper floor's room furnished too: pieces along its back walls (and the
## dividing wall's), clear of the stairwell and the doorways onto the terrace,
## the same mix as downstairs - and at least one container.
func _furnish_upper(b: BuiltBuilding) -> void:
	var f: BuildingFloors.Floor = b.upper
	if f == null:
		return
	var room := f.room
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(b.spec) + 11
	var avoid := {}
	for c in [f.stair_0, f.stair_1, f.landing]:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				avoid[c + Vector2i(dx, dy)] = true
	var walls := {}
	for i in range(room.position.x, room.end.x):
		for j in range(room.position.y, room.end.y):
			var sides := []
			if i == room.position.x:
				sides.append("nw")
			if j == room.position.y:
				sides.append("ne")
			if not sides.is_empty():
				walls[Vector2i(i, j)] = sides
	if room.size.x >= 5:   # the dividing wall (BuildingFloors.add)
		var wx := room.position.x + room.size.x / 2
		for j in range(room.position.y, room.end.y):
			var list: Array = walls.get(Vector2i(wx, j), [])
			list.append("nw")
			walls[Vector2i(wx, j)] = list
	var cells := walls.keys()
	cells.sort()
	for k in range(cells.size() - 1, 0, -1):   # shuffled (seeded)
		var m := rng.randi() % (k + 1)
		var t: Vector2i = cells[k]
		cells[k] = cells[m]
		cells[m] = t
	var opened: Dictionary = state["planets"].get(planet_id, {}).get("opened", {})
	var picks: Array = _furniture_for(b.style)
	var limit := maxi(2, room.size.x * room.size.y / 9)
	var count := {}
	var used := {}
	var place := func(c: Vector2i, kind: String) -> Furniture:
		var placed := _place_upper_piece(b, kind, walls[c][rng.randi() % walls[c].size()], c, opened)
		if placed:
			count[kind] = count.get(kind, 0) + 1
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					used[c + Vector2i(dx, dy)] = true
		return placed
	for c in cells:
		if f.furniture.size() >= limit:
			break
		if avoid.has(c) or used.has(c) or rng.randf() < 0.3:
			continue
		var kind: String = picks[rng.randi() % picks.size()]
		if count.get(kind, 0) >= MAX_EACH_KIND:
			continue
		place.call(c, kind)
	if not f.furniture.any(func(p): return p.is_container()):
		for c in cells:
			if not avoid.has(c) and not used.has(c) and place.call(c, "chest") != null:
				break


## One piece upstairs, if it fits: on the upper floor's open floor, away from
## its doorways. Its key ends in "^" (its own, not the piece below's).
func _place_upper_piece(b: BuiltBuilding, kind: String, wall: String, cell: Vector2i, opened: Dictionary) -> Furniture:
	var fl: BuildingFloors.Floor = b.upper
	var f: Furniture = Furniture.new().setup(kind, wall, cell, _cell_pos(cell), b.style)
	f.key += "^"
	f.seed_ = hash(f.key + f.kind)
	var probe := [f.position, (f.footprint[1] + f.footprint[2]) * 0.5 if wall == "nw" else (f.footprint[2] + f.footprint[3]) * 0.5]
	if f.is_container():
		probe.append(f.approach())
	for p in probe:
		if not BuildingFloors.walkable(self, b, p, 10.0):
			f.free()
			return null
		for dw in fl.doorways:
			if p.distance_to(dw[0] + dw[1] * 0.5) < 60.0:
				f.free()
				return null
	if f.is_container() and opened.has(f.key):
		f.opened = true
		f._update_title()
	fl.node.add_child(f)
	fl.furniture.append(f)
	if not f.is_flat():
		fl.blocks.append(f.footprint)
	return f


## Where a thing stands on the ground plane (upstairs furniture is drawn a
## storey up: its own position is the ground-plane one).
func _ground_of(t: Node2D) -> Vector2:
	return t.position if t is Furniture else t.global_position


## Opening a chest, locker or vault: what's inside is yours (once).
func open_container(f: Furniture) -> void:
	if f.opened:
		show_prompt("The %s is empty." % f.display_name().to_lower(), 2.0)
		return
	if Inventory.slots_used(carried()) >= Inventory.PLAYER_SLOTS:
		show_prompt("You can't carry any more (%d slots) - take things to your ship first." % Inventory.PLAYER_SLOTS, 2.5)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(planet_id + f.key)
	var got := []
	match f.kind:
		"chest":
			got.append(["credits", rng.randi_range(20, 70)])
			if rng.randf() < 0.45:
				got.append([["scrap", "energy_cell", "medicine", "repair_kit", "energy_drink"].pick_random(), 1])
		"locker":
			var opts := [["energy_cell", 2], ["repair_kit", 1], ["missile", 3], ["scrap", 3], ["medicine", 1], ["energy_drink", 2]]
			got.append(opts[rng.randi() % opts.size()])
			if rng.randf() < 0.4:
				got.append(["credits", rng.randi_range(10, 30)])
		"vault":
			got.append(["credits", rng.randi_range(100, 240)])
			if rng.randf() < 0.35:
				got.append(["data_core", 1])
			if rng.randf() < 0.3:
				got.append(["alien_alloy", 1])
	# Gear (Gear): automaton equipment - often in a vault, now and then elsewhere.
	if rng.randf() < CONTAINER_GEAR_CHANCE.get(f.kind, 0.0):
		got.append([Gear.roll(rng, "foot", 0.6 if f.kind == "vault" else 0.3), 1])
	var parts := []
	for g in got:
		_give(g[0], g[1])
		parts.append("%d %s" % [g[1], "credits" if g[0] == "credits" else Items.display_name(g[0])])
	f.set_opened(true)
	var pl: Dictionary = state["planets"][planet_id]
	if not pl.has("opened"):
		pl["opened"] = {}
	pl["opened"][f.key] = true
	Sfx.play_at("surface/%s_open" % f.kind, f.position, objects, -3.0)
	Sfx.play("pirate/loot_take", -4.0)
	show_prompt("%s: %s" % [f.display_name(), ", ".join(parts)], 3.0)


func _remove_building(b: BuiltBuilding) -> void:
	for w in b.walls + b.columns + b.decor:
		_occluders.erase(w)
		w.queue_free()
	for f in b.furniture:
		f.queue_free()
	for d in b.doors:
		d.queue_free()
	b.roof.queue_free()
	if b.upper != null:
		for n in [b.upper.node, b.upper.up_thing, b.upper.down_thing]:
			n.queue_free()
		if level_b == b:
			_set_level(0, null)
	for i in range(b.rect.position.x, b.rect.end.x):
		for j in range(b.rect.position.y, b.rect.end.y):
			floor_layer.erase_cell(Vector2i(i, j))
	for z in b.door_zones:
		_door_zones.erase(z)
	buildings.erase(b)
	_bgrid_ok = false
	_blocked_cells.clear()
	for o in buildings:
		for i in range(o.rect.position.x - 1, o.rect.end.x + 1):
			for j in range(o.rect.position.y - 1, o.rect.end.y + 1):
				_blocked_cells[Vector2i(i, j)] = true


func get_layout() -> Dictionary:
	var h := []
	for v in _height:
		h.append(snappedf(v - LAND_BIAS, 0.001))   # (added back when loaded)
	# Every building and citizen - built yet or still only planned out there.
	var specs := []
	for b in buildings:
		var spec: Dictionary = b.spec.duplicate(true)
		spec["title"] = b.title
		specs.append(spec)
	for p in _plans:
		if p["built"] == null:
			specs.append(p["spec"].duplicate(true))
	var people: Array = npcs.map(func(a): return [roundi(a.position.x), roundi(a.position.y), a.variant] + (["pirate"] if a.species == "pirate" else []))
	for n in _npc_plans:
		if not n["spawned"]:
			people.append([roundi(n["pos"].x), roundi(n["pos"].y), n["variant"]] + (["pirate"] if n.get("kind") == "pirate" else []))
	# Only scenery placed by hand: the planet's own grows back by itself.
	var kept := _props.keys().filter(func(p): return is_instance_valid(p) \
		and (not p.has_meta("chunk") if p is Node else p.chunk == Vector2i(-1, -1)))
	return {
		"_help": "Planet surface layout made in the Level Editor (right-click > Level Editor). heights: %dx%d terrain heights; buildings: blueprints; npcs (Minoan citizens and pirates): [x, y, variant(, pirate)]; props: scenery placed by hand [kind, x, y, scale, colour, variant] (the rest grows by itself). Delete this file (or use 'Revert to generated') to go back to the generated planet." % [N, N],
		"planet": planet_id,
		"heights": h,
		"buildings": specs,
		"npcs": people,
		"props": kept.map(func(p):
			return [p.kind, roundi(p.position.x), roundi(p.position.y), snappedf(p.s, 0.01), p.color.to_html(false), p.variant]),
	}


func _context_menu(at: Vector2) -> void:
	UI.context_menu(self, at, [
		["Leave planet...", confirm_leave],
		["Map  (M)", func(): field_menu.open(field_menu.MAP_TAB)],
		["Level Editor...", func(): level_editor.open()],
	])


# Level editor host API (see level_editor.gd).

func editor_title() -> String:
	return "LEVEL EDITOR  ·  %s" % pdata["name"]


func editor_tools() -> Array:
	return [
		{"id": "terrain", "label": "Paint terrain", "options": pdata["terrain"].map(func(t): return t[0]), "brush": true, "drag": true,
			"help": "Click or drag to paint the chosen ground type."},
		{"id": "building", "label": "Draw building", "options": ["Minoan palace", "Minoan warehouse", "Minoan temple"], "rect": true,
			"help": "Drag a rectangle: buildings are at least 12 x 12 tiles (a smaller drag is enlarged). The ground under it is levelled. It gets a door in the middle of its front wall."},
		{"id": "wall", "label": "Wall: plain / window / door",
			"help": "Click a wall to cycle it: plain, window, door."},
		{"id": "column", "label": "Place column", "help": "Click a tile inside a building to add a Minoan column."},
		{"id": "npc", "label": "Place Minoan citizen", "options": ["Minoan guard (laser rifle)", "Minoan android (laser rifle)", "Minoan android (laser bow)", "Minoan android (labrys)"], "help": "Click to place a Minoan citizen."},
		{"id": "prop", "label": "Place scenery", "options": PROP_KINDS, "drag": true, "help": "Click (or drag) to place scenery."},
		{"id": "erase", "label": "Erase", "drag": true,
			"help": "Click a citizen, column or scenery to remove it; click inside a building (with nothing else there) to remove the building."},
	]


func editor_apply(tool: String, opt: int, brush: int, world: Vector2, phase: String, start: Vector2) -> void:
	match tool:
		"terrain":
			if phase == "release":
				_after_terrain_edit()
			else:
				paint_terrain(world, opt, brush)
		"building":
			if phase == "release":
				var r := _cell_rect(start, world)
				r.size = r.size.max(Vector2i(MIN_BUILDING, MIN_BUILDING))   # (at least 12 x 12)
				if r.position.x >= 2 and r.position.y >= 2 and r.end.x <= N - 2 and r.end.y <= N - 2:
					_clear_site(r)
					_refresh_terrain(r.grow(4))
					_clear_props(r)
					var door := Vector2i(r.position.x + r.size.x / 2, r.end.y - 1)
					var st: String = ["palace", "warehouse", "temple"][opt]
					var b := _build_from_spec({"rect": [r.position.x, r.position.y, r.size.x, r.size.y],
						"material": "minoan", "style": st, "doors": [[door.x, door.y, "sw"]]})
					b.title = "Minoan %s" % st
					_build_nav()
		"wall":
			if phase == "press":
				_cycle_wall(world)
		"column":
			if phase == "press":
				var cell := tilemap.local_to_map(world)
				for b in buildings:
					if b.rect.has_point(cell):
						_add_column(b, cell)
						_build_nav()
		"npc":
			if phase == "press" and walkable_at(world):
				_spawn_npc(world, opt + PROPS.CITIZENS.size() * randi_range(0, 7), world)
		"prop":
			var free := true
			for p in _props:
				if is_instance_valid(p) and p.position.distance_to(world) < 40.0:
					free = false
			if phase == "press" or (phase == "drag" and free):
				var kind: String = PROP_KINDS[opt]
				var col: Color = pdata["prop_color"]
				if kind in ["rock", "boulder", "pebbles"]:
					col = Color(0.5, 0.5, 0.53)
				elif kind == "tuft":
					col = Color(0.38, 0.62, 0.28)
				elif kind == "flowers":
					col = Color(1.0, 0.6, 0.78)
				_spawn_prop(kind, col, randf_range(0.85, 1.25), randi(), world)
		"erase":
			if phase != "release":
				_erase_at(world)


func paint_terrain(world: Vector2, t: int, radius: int) -> void:
	var thresholds: Array = pdata["thresholds"]
	var lo: float = thresholds[t - 1] if t > 0 else thresholds[0] - 0.3
	var hi: float = thresholds[t] if t < thresholds.size() else thresholds[-1] + 0.3
	var h := (lo + hi) * 0.5
	var c := tilemap.local_to_map(world)
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var q := c + Vector2i(dx, dy)
			if q.x < 0 or q.y < 0 or q.x >= N or q.y >= N or Vector2(dx, dy).length() > radius + 0.3:
				continue
			_height[q.x * N + q.y] = h
			_terrain[q.x * N + q.y] = t
			var k := q.x * N + q.y
			_rock[k] = 0   # (painting ground over a crag or cliff removes it, and makes a slope)
			_cliff[k] = 0
			_crag[k] = 0
			_ramp[k] = 1.0
			_elev[k] = TERRAIN.elevation(h, 1.0, 0.0, Vector2(q), N, _water_top, _site_h)
			var v := (h + 1.0) * 0.5
			_height_img.set_pixel(q.x, q.y, Color(v, 0.0, 1.0, 0.0))
	_height_tex.update(_height_img)
	_repaint_map(Rect2i(c - Vector2i(radius, radius), Vector2i(radius * 2 + 1, radius * 2 + 1)))


func _after_terrain_edit() -> void:
	_build_nav()
	_minimap.setup(self)


func _cell_rect(a: Vector2, b: Vector2) -> Rect2i:
	var ca := tilemap.local_to_map(a)
	var cb := tilemap.local_to_map(b)
	var p := Vector2i(mini(ca.x, cb.x), mini(ca.y, cb.y))
	return Rect2i(p, Vector2i(absi(ca.x - cb.x) + 1, absi(ca.y - cb.y) + 1))


func editor_rect_polygon(a: Vector2, b: Vector2) -> PackedVector2Array:
	var r := _cell_rect(a, b)
	var g2w := _world_to_grid.affine_inverse()
	var x0 := r.position.x - 0.5
	var y0 := r.position.y - 0.5
	var x1 := r.end.x - 0.5
	var y1 := r.end.y - 0.5
	return PackedVector2Array([g2w * Vector2(x0, y0), g2w * Vector2(x1, y0), g2w * Vector2(x1, y1), g2w * Vector2(x0, y1)])


func _cycle_wall(world: Vector2) -> void:
	var best: Sprite2D = null
	var best_b: BuiltBuilding = null
	var best_d := 24.0
	for b in buildings:
		for w in b.walls:
			var seg: Array = w.get_meta("seg")
			var d := world.distance_to(Geometry2D.get_closest_point_to_segment(world, seg[0], seg[1]))
			if d < best_d:
				best = w
				best_b = b
				best_d = d
	if best == null:
		return
	var order := ["plain", "window", "door"]
	var next: String = order[(order.find(best.get_meta("kind")) + 1) % order.size()]
	var spec: Dictionary = best_b.spec.duplicate(true)
	spec["overrides"][best.get_meta("edge")] = next
	spec["title"] = best_b.title
	_remove_building(best_b)
	_build_from_spec(spec)
	_build_nav()


func _erase_at(world: Vector2) -> void:
	for a in npcs:
		if world.distance_to(a.position + Vector2(0, -40)) < 50.0:
			npcs.erase(a)
			a.queue_free()
			return
	for b in buildings:
		for c in b.columns:
			if world.distance_to(c.position) < 30.0:
				var cell := tilemap.local_to_map(c.position)
				b.spec["columns"] = b.spec["columns"].filter(func(e): return Vector2i(e[0], e[1]) != cell)
				var i: int = b.columns.find(c)
				b.columns.remove_at(i)
				b.pillars.remove_at(i)
				_occluders.erase(c)
				c.queue_free()
				_build_nav()
				return
	var best: Object = null
	var best_d := 36.0
	for p in _props:
		if is_instance_valid(p) and world.distance_to(p.position) < best_d:
			best = p
			best_d = world.distance_to(p.position)
	if best:
		_remove_prop(best)
		return
	var cell := tilemap.local_to_map(world)
	for b in buildings:
		if b.rect.has_point(cell):
			_remove_building(b)
			_build_nav()
			return


func _remove_prop(p: Object) -> void:
	_props.erase(p)
	if p is PROPS.PropData:
		p.batch.items.erase(p)
		p.batch.queue_redraw()
	else:
		_tall_props.erase(p)
		_faded.erase(p)
		p.queue_free()


## Clears the scenery off a plot (its tiles and one around).
func _clear_props(r: Rect2i) -> void:
	var g := r.grow(1)
	for p in _props.keys():
		if is_instance_valid(p) and g.has_point(tilemap.local_to_map(p.position)):
			_remove_prop(p)


func editor_save() -> String:
	_layout = get_layout()
	return DataFiles.write(_layout_path(), _layout)


func editor_revert() -> String:
	for p in [_layout_path(), DataFiles.user_path(_layout_path())]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	level_editor.close()
	SaveGame.travelling = true
	UI.fade_change_scene("res://scenes/planet_surface.tscn")
	return "Reverting to the generated planet..."


func editor_camera() -> Camera2D:
	return pilot.get_node("Camera2D") if pilot.has_node("Camera2D") else get_viewport().get_camera_2d()


# --- Input & movement ---------------------------------------------------------------

# Tab: the Field Computer (I: its inventory); M: the surface map; 1-3 the
# toolbar (in _input so GUI focus navigation can't eat Tab).
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion) or get_tree().paused \
			or surface_map == null or surface_map.visible or field_menu == null or field_menu.visible:
		return
	var slot := Keybinds.slot_pressed(event)
	if Keybinds.pressed(event, "computer"):
		_holding = false
		field_menu.open()
	elif Keybinds.pressed(event, "inventory"):
		_holding = false
		field_menu.open(field_menu.INVENTORY_TAB)
	elif Keybinds.pressed(event, "sector_map"):
		_holding = false
		field_menu.open(field_menu.MAP_TAB)
	elif Keybinds.pressed(event, "skills"):
		_holding = false
		field_menu.open(field_menu.SKILLS_TAB)
	elif slot >= 0:
		if level_editor and level_editor.visible:
			return
		use_tool(slot)
	else:
		return
	get_viewport().set_input_as_handled()


# --- The toolbar on foot (SurfaceToolbar) -------------------------------------------------

var _tool_cd := {}                  # tool id -> s of cooldown left
var _overcharge := 0.0

## Your toolbar on foot (Inventory.toolbar: 9 slots you fill yourself).
func foot_toolbar() -> Array:
	return Inventory.toolbar(state["player"], true)


## What you carry (Inventory.carried: 12 slots).
func carried() -> Dictionary:
	return Inventory.carried(state["player"])


## A toolbar slot (keys 1-9): whatever you put there - the rifle (the nearest
## enemy, as F), medicine (heals), an energy cell (overcharges the rifle).
func use_tool(i: int) -> void:
	var bar := foot_toolbar()
	if i >= 0 and i < bar.size():
		use_item(bar[i])


## Uses a tool on foot ("rifle", "medicine", "energy_cell", food or an energy
## drink: Stamina) - from the toolbar or clicked in the inventory.
func use_item(id: String) -> void:
	if pilot == null or id == "" or float(_tool_cd.get(id, 0.0)) > 0.0 or pilot.busy > 0.0:
		return
	if Skills.is_skill(id):          # (a skill: Skills)
		use_skill(Skills.id_of(id))
		return
	var inv := carried()
	if Stamina.restores(id) > 0.0:   # (food and energy drinks: Stamina)
		if int(inv.get(id, 0)) <= 0:
			show_prompt("No %s with you." % Items.display_name(id), 1.5)
			return
		if pilot.stamina >= Stamina.MAX - 1.0:
			show_prompt("You're not tired.", 1.5)
			return
		var got := minf(Stamina.restores(id), Stamina.MAX - pilot.stamina)
		pilot.stamina += got
		Effects.float_text(pilot.global_position + Vector2(0, -90), "+%d stamina" % int(got), Color(0.55, 1.0, 0.45))
		Inventory.take(inv, id, 1)
		_tool_cd[id] = Stamina.COOLDOWN
		_update_hud()
		return
	match id:
		"rifle":
			pilot.style = "rifle"
			var foe := nearest_hostile(2.0)
			if foe:
				attack(foe)
			else:
				show_prompt("No enemy in sight.", 1.5)
			return
		"medicine":
			if int(inv.get("medicine", 0)) <= 0:
				show_prompt("No medicine with you - pirates and traders carry it, or take some from your ship.", 2.5)
				return
			if pilot.hp >= pilot.max_hp:
				show_prompt("You're not hurt.", 1.5)
				return
			pilot.hp = minf(pilot.max_hp, pilot.hp + SurfaceToolbar.HEAL)
			Effects.float_text(pilot.global_position + Vector2(0, -90), "+%d health" % int(SurfaceToolbar.HEAL), Color(0.4, 1.0, 0.5))
		"energy_cell":
			if int(inv.get("energy_cell", 0)) <= 0:
				show_prompt("No energy cells with you.", 1.5)
				return
			_overcharge = SurfaceToolbar.OVERCHARGE * pilot.overcharge_mult   # (a Fusion Core: longer)
			Effects.float_text(pilot.global_position + Vector2(0, -90), "Rifle overcharged!", Color(0.45, 0.9, 1.0))
		_:
			return
	Inventory.take(inv, id, 1)
	_tool_cd[id] = float(SurfaceToolbar.COOLDOWN.get(id, 0.0))
	_update_hud()


## Cooldown left on a toolbar slot's tool.
func tool_cooldown(i: int) -> float:
	var bar := foot_toolbar()
	return float(_tool_cd.get(bar[i], 0.0)) if i >= 0 and i < bar.size() else 0.0


var _was_tired := false


## Seconds of the energy cell's overcharge left (the rifle fires twice as fast).
func overcharge_left() -> float:
	return _overcharge


func _update_tools(delta: float) -> void:
	for k in _tool_cd:
		_tool_cd[k] = maxf(0.0, float(_tool_cd[k]) - delta)
	_overcharge = maxf(0.0, _overcharge - delta)
	_update_skills(delta)
	if pilot:
		state["player"]["stamina"] = pilot.stamina   # (kept with you: Stamina)
		if pilot.tired() != _was_tired:
			_was_tired = pilot.tired()
			if _was_tired:
				show_prompt("Out of stamina: you walk slowly and don't heal - eat something, or drink an Energy Drink.", 4.0)


## You were hit: the full-window map closes, so you see the fight.
func close_menus_on_hit() -> void:
	if UI.esc_menu_open():
		return
	if surface_map != null and surface_map.visible:
		surface_map.close()
		show_prompt("Under attack!", 1.5)
	if field_menu != null and field_menu.visible:
		field_menu.close()
		show_prompt("Under attack!", 1.5)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or Keybinds.pressed(event, "pause"):
		pause_menu.open()
		get_viewport().set_input_as_handled()
		return
	if surface_map != null and surface_map.visible:
		return   # (the map's keys are its own; the game goes on behind it)
	# Fighting on foot: click an enemy (left or right) to attack it - you close
	# in if it's out of range and fire until it falls; F attacks the nearest.
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] \
			and not _climbing and level == 0:
		var foe := _hostile_at(get_canvas_transform().affine_inverse() * event.position)   # (drawn: lifted)
		if foe:
			attack(foe)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_holding = false
		_context_menu(event.position)
		get_viewport().set_input_as_handled()
		return
	if Keybinds.pressed(event, "attack"):
		var foe := nearest_hostile(2.0)
		if foe:
			attack(foe)
		else:
			show_prompt("No enemy in sight.", 1.5)
		get_viewport().set_input_as_handled()
		return
	# Mouse wheel: zoom in / out.
	if event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var step := ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
		_zoom = clampf(_zoom * step, ZOOM_MIN, ZOOM_MAX)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and UI.middle_click(self, event):
		_zoom = 1.0   # (the middle button: back to the normal zoom)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouse:
		_last_mouse = event.position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _climbing:
				return
			var world: Vector2 = get_canvas_transform().affine_inverse() * event.position
			stop_attack()   # (a click elsewhere ends the fight)
			var thing := _thing_at(world)
			if thing:
				_pending_target = []
				_target_thing = thing
				_walk_to(thing.approach() if thing.has_method("approach") else thing.global_position + Vector2(0, 30))
			else:
				_target_thing = null
				_pending_target = []
				var dest := _click_target(screen_to_ground(world) if level == 0 else world)
				if dest[1] == level and (level == 0 or dest[2] == level_b):
					_holding = true   # (hold to keep walking: on this floor)
					_press_ms = Time.get_ticks_msec()
					_walk_to(dest[0])
				else:
					_route_to(dest)
		else:
			_holding = false
	elif event is InputEventMouseMotion and not _holding:
		var world: Vector2 = get_canvas_transform().affine_inverse() * event.position
		var foe := _hostile_at(world) if level == 0 else null
		if foe:   # an enemy under the cursor: crosshair
			Input.set_default_cursor_shape(Input.CURSOR_CROSS)
			_hovered = foe
			show_prompt("%s  -  click to attack" % foe.title.get_slice("  -", 0), 0.6)
			return
		var thing := _thing_at(world)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if thing else Input.CURSOR_ARROW)
		_hovered = thing
		if thing:
			show_prompt(thing.title, 0.6)


## The enemy under the cursor (group "surface_hostiles"), or null.
func _hostile_at(world: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for h in _targets():
		# Anywhere on the figure (about 100 x 140 px over its feet - an animal: its
		# own size, up in the air if it flies), with a little slack.
		var hp: Vector2 = h.global_position - Vector2(0, lift_at(h.global_position))   # (as drawn)
		var box := Rect2(hp + Vector2(-50, -145), Vector2(100, 160))
		var mid := hp + Vector2(0, -60)
		if h is SurfaceCreature:
			var ht: float = h.height
			var w := maxf(70.0, ht * 1.1)
			box = Rect2(hp + Vector2(-w * 0.5, -h._alt - ht - 12.0), Vector2(w, ht + 26.0))
			mid = hp + Vector2(0, -h._alt - ht * 0.5)
		if not box.has_point(world):
			continue
		var d: float = world.distance_to(mid)
		if d < best_d:
			best = h
			best_d = d
	return best


## What you can fire at: the enemies (group "surface_hostiles") and every animal.
func _targets() -> Array:
	var out: Array = get_tree().get_nodes_in_group("surface_hostiles")
	for c in creatures:
		if is_instance_valid(c) and not c.dead and not c.hostile:
			out.append(c)
	return out


## The nearest enemy within your rifle's reach (times `reach`), or null.
func nearest_hostile(reach := 1.0) -> Node2D:
	var best: Node2D = null
	var best_d: float = pilot.reach * reach
	for h in get_tree().get_nodes_in_group("surface_hostiles"):
		var d: float = pilot.position.distance_to(h.position)
		if d < best_d:
			best = h
			best_d = d
	return best


# --- Fights on foot ----------------------------------------------------------------------

## The enemy you're fighting (attack): you close in until it's in range,
## then fire until it falls - or you click elsewhere, or it gets away.
var _attack_target: Node2D
var _attack_repath := 0.0
const GIVE_UP := 1400.0              # px: it got away

func attack(foe: Node2D) -> void:
	_attack_target = foe
	_attack_repath = 0.0
	_target_thing = null
	_far_goal = Vector2.INF
	_holding = false


func stop_attack() -> void:
	_attack_target = null
	if pilot:
		pilot.trigger = null


func _update_attack(delta: float) -> void:
	var foe := _attack_target
	if foe == null:
		_fire_back()
		return
	if not is_instance_valid(foe) or foe.get("dead") == true \
			or not (foe.is_in_group("surface_hostiles") or foe.is_in_group("surface_creatures")) \
			or pilot.position.distance_to(foe.position) > GIVE_UP or level != 0 or _climbing:
		var fell: bool = not is_instance_valid(foe) or foe.get("dead") == true
		stop_attack()
		var next := _next_attacker() if fell and level == 0 and not _climbing else null
		if next:
			attack(next)   # (one down: on to the next that's going for you)
		return
	var d := pilot.position.distance_to(foe.position)
	if pilot.busy > 0.0:
		return   # (in the middle of a move)
	if pilot.style != "rifle":
		# A martial style: close in, then work through its chain of blows.
		pilot.trigger = null
		# (in the middle of a chain it steps in with the next blow: a little further will do)
		if d > Skills.MELEE_REACH * (1.3 if _combo_t < Skills.COMBO_WINDOW * 0.5 else 0.85):
			_attack_repath -= delta
			if _attack_repath <= 0.0 or not pilot.moving:
				_attack_repath = 0.25
				_walk_to(foe.position)
		else:
			if pilot.moving:
				pilot.moving = false
				pilot.path = PackedVector2Array()
			_next_blow(foe)
		return
	if d > pilot.reach * 0.9 or not shot_clear(pilot.position, foe.position):
		# Out of range, or a wall / rock in the way: walk toward it (re-planned as it moves).
		pilot.trigger = null
		_attack_repath -= delta
		if _attack_repath <= 0.0 or not pilot.moving:
			_attack_repath = 0.4
			_walk_to(foe.position)
	else:
		# In range: stand and fire.
		if pilot.moving:
			pilot.moving = false
			pilot.path = PackedVector2Array()
		pilot.trigger = foe


## Not fighting anyone, but something just bit you: you shoot back at it
## (while walking on - you can still run for it), until it falls or you're clear.
func _fire_back() -> void:
	if pilot.trigger != null or level != 0 or _climbing or Time.get_ticks_msec() - bitten_at > 1500 or pilot.busy > 0.0:
		return
	var c: Node2D = bitten_by_node
	if pilot.style != "rifle":       # (in a martial style: it turns on what bit it, if it's right there)
		if is_instance_valid(c) and c.get("dead") != true and pilot.position.distance_to(c.position) < Skills.MELEE_REACH * 1.6 and not pilot.moving:
			attack(c)
		return
	if is_instance_valid(c) and c.get("dead") != true and pilot.position.distance_to(c.position) < pilot.reach:
		pilot.trigger = c


## The nearest enemy within reach that's after you (a beast hunting you, a
## pirate aiming at you), or null.
func _next_attacker() -> Node2D:
	var best: Node2D = null
	var best_d: float = pilot.reach
	for h in _targets():
		if h.get("dead") == true or not (h.get("_threat") == pilot or h.get("_aim_at") == pilot):
			continue
		var d: float = pilot.position.distance_to(h.position)
		if d < best_d:
			best = h
			best_d = d
	return best


# --- Skills (Skills): martial arts, the leap, the arcana ----------------------------------

var _move := {}                     # the move under way: {kind, t, time, ...}
var _combo_i := 0                   # the next blow of the style's chain
var _combo_t := 99.0                # s since the last blow ended
var _beams: Array = []              # beams still burning: {a, b, width, damage, left, t}
var _burns: Array = []              # what's on fire: {node, dps, left, t}
const SPELL_COLORS := {"lance": Color(1.0, 0.85, 0.4), "phlox": Color(1.0, 0.5, 0.15), "keraunos": Color(0.7, 0.85, 1.0),
	"aegis": Color(0.45, 0.8, 1.0), "eidola": Color(0.5, 0.95, 1.0)}


## Where a skill is aimed: `skill_at` if given (use_skill's `at`: tests, scripted
## use), a way ahead of you on a gamepad, else where the mouse points on the ground.
var skill_at := Vector2.INF

func mouse_ground() -> Vector2:
	if skill_at != Vector2.INF:
		return skill_at
	if _pad_walk and pilot:
		return pilot.position + pilot.heading.normalized() * 420.0
	var world: Vector2 = get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
	return screen_to_ground(world) if level == 0 else world


## Who a skill goes for: the enemy under the cursor, else the one you're
## fighting, else the nearest - within `reach` px; null if none.
func _skill_foe(reach: float) -> Node2D:
	var world: Vector2 = get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
	var best: Node2D = null
	for c in [_hostile_at(world) if level == 0 else null, _attack_target]:
		if c != null and is_instance_valid(c) and c.get("dead") != true and pilot.position.distance_to(c.position) <= reach:
			return c
	var best_d := reach
	for h in get_tree().get_nodes_in_group("surface_hostiles"):
		var d: float = pilot.position.distance_to(h.position)
		if d < best_d and h.get("dead") != true:
			best = h
			best_d = d
	return best


## Who a spell's burst, a sweep or a leaping thunderbolt can hit: the enemies
## (group "surface_hostiles"), an animal that's hunting, and whatever you aimed
## at or are fighting (`also`) - not the peaceful animals that happen to stand near.
func _foes(also: Variant = null) -> Array:
	var out: Array = get_tree().get_nodes_in_group("surface_hostiles")
	for c in [also, _attack_target]:
		if c != null and is_instance_valid(c) and not out.has(c):
			out.append(c)
	return out


## A clip's length and when its mark comes (s) - or the given ones, if the
## automaton's drawn from the classic sheets (no clips).
func _clip_times(clip: String, mark: String, fb_time: float, fb_mark: float) -> Array:
	var pu: SheetPuppet = pilot.puppet
	if pu and pu.clip_mode and pu.clip_frames(clip) > 0:
		var mt := pu.mark_time(clip, mark)
		return [pu.clip_time(clip), mt if mt >= 0.0 else pu.clip_time(clip) * 0.5]
	return [fb_time, fb_mark]


## Uses a skill (from the toolbar: "skill:<id>"; `at`: where it's aimed, else
## the mouse). True if it was performed.
func use_skill(id: String, at := Vector2.INF) -> bool:
	skill_at = at
	var done := _use_skill(id)
	skill_at = Vector2.INF
	return done


func _use_skill(id: String) -> bool:
	if pilot == null or not Skills.SKILLS.has(id) or pilot.hp <= 0.0:
		return false
	var p: Dictionary = state["player"]
	var r := Skills.rank(p, id)
	var s: Dictionary = Skills.SKILLS[id]
	if r <= 0:
		show_prompt("%s: not learned yet - see the Field Computer's SKILLS tab." % s["name"], 2.5)
		return false
	if level != 0 or _climbing:
		show_prompt("No room for that up here.", 1.5)
		return false
	if s["kind"] == "style":
		pilot.style = id
		pilot.fought()
		_combo_i = 0
		var foe := _skill_foe(620.0)
		if foe:
			attack(foe)
		else:
			show_prompt("%s  -  click an enemy to fight it hand to hand." % s["name"], 2.0)
		_update_hud()
		return true
	var item := Skills.item_of(id)
	if pilot.busy > 0.0 or float(_tool_cd.get(item, 0.0)) > 0.0:
		return false
	if pilot.stamina < Skills.stamina(id):
		show_prompt("Too tired for %s - eat something, or drink an Energy Drink." % s["name"], 2.2)
		return false
	var ok := false
	match str(s["kind"]):
		"move":
			ok = _skill_move(id, r)
		"guard":
			ok = _skill_guard(id, r)
		"leap":
			ok = _skill_leap(id, r)
		"beam", "fireball", "lightning", "dome", "minions":
			ok = _skill_cast(id, r)
	if ok:
		pilot.stamina = maxf(0.0, pilot.stamina - Skills.stamina(id))
		_tool_cd[item] = Skills.cooldown(id, r)
		pilot.fought()
		_update_hud()
	return ok


## The next blow of the style you fight in, thrown at `foe` (in reach).
func _next_blow(foe: Node2D) -> void:
	var id: String = pilot.style
	if not Skills.SKILLS.has(id) or Skills.SKILLS[id]["kind"] != "style":
		pilot.style = "rifle"
		return
	var r := maxi(1, Skills.rank(state["player"], id))
	if pilot.stamina < Skills.stamina(id):
		show_prompt("Too tired to fight - eat something, or drink an Energy Drink.", 2.2)
		stop_attack()
		return
	var chain := Skills.chain(id, r)
	if _combo_t > Skills.COMBO_WINDOW:
		_combo_i = 0
	var move: String = chain[_combo_i % chain.size()]
	_combo_i = (_combo_i + 1) % chain.size()
	pilot.stamina = maxf(0.0, pilot.stamina - Skills.stamina(id))
	_start_blow(move, r, foe, id)


func _start_blow(move: String, r: int, foe: Node2D, skill: String) -> void:
	var m: Dictionary = Skills.MOVES[move]
	var tm := _clip_times(str(m["clip"]), "hit", 0.36, 0.14)
	if is_instance_valid(foe):
		pilot.face(foe.position - pilot.position)
		# A step in with the blow, if it was shoved a little out of reach.
		var gap: float = pilot.position.distance_to(foe.position) - Skills.MELEE_REACH * 0.75
		if gap > 0.0 and gap < 40.0:
			var to: Vector2 = pilot.position + pilot.position.direction_to(foe.position) * gap
			if _p_walkable(to):
				pilot.position = to
	pilot.perform(str(m["clip"]), tm[0])
	_move = {"kind": "blow", "move": move, "rank": r, "skill": skill, "foe": foe, "t": 0.0, "at": tm[1], "time": tm[0], "done": false}
	Sfx.play_at("skill/whoosh", pilot.position, objects, -8.0)


## The blow under way lands: on its target, or (a roundhouse, a sweep) on
## everyone it reaches.
func _land_blow(mv: Dictionary) -> void:
	var m: Dictionary = Skills.MOVES[mv["move"]]
	var dmg := Skills.blow_damage(str(mv["move"]), int(mv["rank"]))
	var facing: Vector2 = pilot.heading.normalized()
	var victims: Array = []
	var col := Skills.school_color(str(mv["skill"]))
	if m.get("ring", false):
		var rad: float = Skills.spell("sweep", int(mv["rank"]))["radius"]
		for t in _foes(mv.get("foe")):
			if t.get("dead") != true and pilot.position.distance_to(t.position) < rad:
				victims.append(t)
		SkillFx.arc(objects, pilot.position, facing, rad, col, true)
	elif m.get("arc", false):
		for t in _foes(mv.get("foe")):
			var d: Vector2 = t.position - pilot.position
			if t.get("dead") != true and d.length() < Skills.MELEE_REACH * 1.5 and (d.length() < 24.0 or d.normalized().dot(facing) > 0.1):
				victims.append(t)
		SkillFx.arc(objects, pilot.position, facing, Skills.MELEE_REACH * 1.4, col)
	else:
		var foe = mv.get("foe")
		if foe != null and is_instance_valid(foe) and foe.get("dead") != true \
				and pilot.position.distance_to(foe.position) < Skills.MELEE_REACH * (1.9 if mv["kind"] == "comet" else 1.45):
			victims.append(foe)
	for t in victims:
		_strike(t, dmg, m)
	if victims.is_empty():
		return
	if pilot.puppet:
		pilot.puppet.frozen = 0.045     # (a hit pause: the blow lands)
	Sfx.play_at("skill/kick" if str(m["clip"]) in ["front", "side", "round", "spin", "sweep", "flykick", "knee"] else "skill/punch",
		pilot.position, objects, -1.0)
	gain_xp(Skills.XP_BLOW * victims.size())


## A blow of yours on `t`: damage (a critical now and then; most of it gone if
## it's blocked), a shove, a stagger - or it goes down.
func _strike(t: Node2D, dmg: float, m: Dictionary) -> void:
	var blocked: bool = t.has_method("try_block") and t.try_block()
	var cr: Array = Upgrades.crit(dmg, pilot.crit_chance, pilot.crit_mult)
	var d: float = float(cr[0]) * (0.35 if blocked else 1.0)
	var away: Vector2 = (t.position - pilot.position).normalized()
	var up = t.get("_alt")
	var chest: Vector2 = t.position + Vector2(0, -52.0 - (float(up) if up != null else 0.0))
	if "last_hit_by" in t:
		t.last_hit_by = pilot
	t.surface_hit(d, "kinetic")
	if is_instance_valid(t) and t.has_method("attacked_by"):
		t.attacked_by(pilot)
	if blocked:
		Effects.float_text(chest + Vector2(0, -40), "BLOCKED", Color(0.8, 0.85, 0.95))
		SkillFx.impact(objects, chest, Color(0.7, 0.8, 1.0), 0.7)
		return
	if cr[1]:
		Effects.float_text(chest + Vector2(0, -40), "CRITICAL", Color(1.0, 0.8, 0.3))
	SkillFx.impact(objects, chest, Color(1.0, 0.85, 0.5), 1.3 if m.get("down", false) else 1.0)
	if not is_instance_valid(t) or t.get("dead") == true:
		return
	_shove(t, away * float(m.get("push", 0.0)))
	if t.has_method("stagger"):
		t.stagger(float(m.get("stagger", 0.3)), bool(m.get("down", false)))
	var pu = t.get("puppet")
	if pu is SheetPuppet:
		pu.frozen = 0.06


## Pushes something over the ground (as far as it's walkable).
func _shove(t: Node2D, by: Vector2) -> void:
	var n := ceili(by.length() / 8.0)
	for i in n:
		var step := by / float(n)
		if not walkable_at(t.position + step):
			break
		t.position += step


## A spell's damage on `t` (energy, heat...), a stagger if `stun` > 0.
func _spell_hit(t: Node2D, dmg: float, dtype := "energy", stun := 0.0) -> void:
	if not is_instance_valid(t) or t.get("dead") == true:
		return
	if "last_hit_by" in t:
		t.last_hit_by = pilot
	t.surface_hit(dmg, dtype)
	if is_instance_valid(t) and t.has_method("attacked_by"):
		t.attacked_by(pilot)
	if stun > 0.0 and is_instance_valid(t) and t.get("dead") != true and t.has_method("stagger"):
		t.stagger(stun)


# Single techniques: the sweep (where you stand), the comet kick (across to an enemy).
func _skill_move(id: String, r: int) -> bool:
	if id == "sweep":
		_start_blow("sweep", r, null, id)
		return true
	var reach := Skills.reach(id, r)
	var foe := _skill_foe(reach)
	if foe == null:
		show_prompt("No enemy within reach of a %s." % Skills.SKILLS[id]["name"], 2.0)
		return false
	var dir := pilot.position.direction_to(foe.position)
	var to := _leap_spot(foe.position - dir * 46.0, reach)
	var pu: SheetPuppet = pilot.puppet
	var tm := [0.6, 0.12, 0.3, 0.5]      # time, off, hit, land
	if pu and pu.clip_mode and pu.clip_frames("flykick") > 0:
		tm = [pu.clip_time("flykick"), pu.mark_time("flykick", "off"), pu.mark_time("flykick", "hit"), pu.mark_time("flykick", "land")]
	pilot.face(foe.position - pilot.position)
	pilot.perform("flykick", tm[0])
	_move = {"kind": "comet", "move": "comet", "rank": r, "skill": id, "foe": foe, "from": pilot.position, "to": to,
		"t": 0.0, "off": tm[1], "at": tm[2], "land": tm[3], "time": tm[0], "done": false}
	if pilot.style == "rifle":           # (it lands in a fight: on with fists and feet, if it knows a style)
		for st in ["laktisma", "pankration", "pygmachia"]:
			if Skills.rank(state["player"], st) > 0:
				pilot.style = st
				break
	attack(foe)
	Sfx.play_at("skill/leap", pilot.position, objects, -3.0)
	return true


func _skill_guard(id: String, r: int) -> bool:
	var sp := Skills.spell(id, r)
	pilot.guard_left = float(sp["time"])
	pilot.guard_soak = float(sp["soak"])
	pilot.perform("block", float(sp["time"]), 1.0, true)
	_move = {"kind": "guard", "t": 0.0, "time": float(sp["time"]), "done": true}
	SkillFx.ring(objects, pilot.position, 46.0, Skills.school_color(id), 0.3)
	Sfx.play_at("skill/guard", pilot.position, objects, -4.0)
	return true


## Where a leap toward `goal` comes down: the furthest spot that way (within
## `reach`) you can stand on, with nothing solid between.
func _leap_spot(goal: Vector2, reach: float) -> Vector2:
	var from: Vector2 = pilot.position
	var dir := from.direction_to(goal)
	var d := minf(reach, from.distance_to(goal))
	while d > 30.0:
		var p := from + dir * d
		if _p_walkable(p) and shot_clear(from, p):
			return p
		d -= 12.0
	return from


func _skill_leap(id: String, r: int) -> bool:
	var to := _leap_spot(mouse_ground(), Skills.reach(id, r))
	if to.distance_to(pilot.position) < 40.0:
		show_prompt("No room to leap that way.", 1.5)
		return false
	var pu: SheetPuppet = pilot.puppet
	var tm := [0.6, 0.1, 0.5]            # time, off, land
	if pu and pu.clip_mode and pu.clip_frames("leap") > 0:
		tm = [pu.clip_time("leap"), pu.mark_time("leap", "off"), pu.mark_time("leap", "land")]
	pilot.face(to - pilot.position)
	pilot.perform("leap", tm[0])
	_move = {"kind": "leap", "from": pilot.position, "to": to, "t": 0.0, "off": tm[1], "land": tm[2], "time": tm[0], "done": false,
		"shock": float(Skills.spell(id, r)["shock"])}
	Sfx.play_at("skill/leap", pilot.position, objects, -3.0)
	return true


const CAST_CLIPS := {"lance": "cast_bolt", "phlox": "cast_bolt", "keraunos": "cast_sky", "aegis": "cast_dome", "eidola": "cast_summon"}

## A spell: the casting pose, then (at the clip's "cast" mark) what it does.
func _skill_cast(id: String, r: int) -> bool:
	var sp := Skills.spell(id, r)
	var reach: float = float(sp["range"])
	var foe: Node2D = _skill_foe(reach) if reach > 0.0 else null
	var point: Vector2 = pilot.position
	if reach > 0.0:
		point = foe.position if foe else pilot.position + (mouse_ground() - pilot.position).limit_length(reach)
		if point.distance_to(pilot.position) < 8.0:
			point = pilot.position + pilot.heading.normalized() * 200.0
		pilot.face(point - pilot.position)
	var clip: String = CAST_CLIPS[id]
	var tm := _clip_times(clip, "cast", 0.65, 0.33)
	pilot.perform(clip, tm[0])
	_move = {"kind": "cast", "id": id, "rank": r, "foe": foe, "point": point, "t": 0.0, "at": tm[1], "time": tm[0], "done": false}
	var hands: Vector2 = pilot.puppet.point(clip, "hands") if pilot.puppet else Vector2(0, -70)
	SkillFx.charge(pilot, hands + Vector2(0, -pilot.lift), SPELL_COLORS[id], float(tm[1]))
	Sfx.play_at("skill/cast", pilot.position, objects, -3.0)
	return true


## The spell being cast lets go.
func _cast_now(mv: Dictionary) -> void:
	var id: String = mv["id"]
	var sp := Skills.spell(id, int(mv["rank"]))
	var col: Color = SPELL_COLORS[id]
	var from: Vector2 = pilot.position
	var point: Vector2 = mv["point"]
	var foe = mv.get("foe")
	if foe != null and is_instance_valid(foe) and foe.get("dead") != true:
		point = foe.position
	var dir: Vector2 = from.direction_to(point) if from.distance_to(point) > 1.0 else pilot.heading.normalized()
	match id:
		"lance":
			# As far as it reaches, or the first wall.
			var end := from
			var d := 0.0
			while d < float(sp["range"]):
				d += 24.0
				if not shot_clear(from, from + dir * d):
					break
				end = from + dir * d
			SkillFx.beam(objects, from + dir * 26.0, end, float(sp["width"]), col, 0.5)
			var n := int(sp["ticks"])
			_beams.append({"a": from, "b": end, "width": float(sp["width"]) * 0.5 + 22.0, "damage": float(sp["damage"]), "left": n, "t": 0.0, "foe": foe})
			Sfx.play_at("skill/beam", from, objects)
		"phlox":
			var goal := from
			var d2 := 0.0
			var far := from.distance_to(point)
			while d2 < far:
				d2 = minf(far, d2 + 24.0)
				if not shot_clear(from, from + dir * d2):
					break
				goal = from + dir * d2
			var fb := SkillFx.Fireball.new()
			fb.position = from + dir * 30.0
			fb.goal = goal
			fb.color = col
			fb.landed.connect(_phlox_burst.bind(sp, foe))
			objects.add_child(fb)
			Sfx.play_at("skill/fire", from, objects)
		"keraunos":
			var first: Node2D = foe if foe != null and is_instance_valid(foe) and foe.get("dead") != true else null
			if first == null:      # (no one aimed at: whoever stands nearest the spot)
				var bd := 90.0
				for t in _foes(foe):
					if t.get("dead") != true and t.position.distance_to(point) < bd:
						first = t
						bd = t.position.distance_to(point)
			SkillFx.bolt(objects, first.position if first else point, col)
			SkillFx.ring(objects, first.position if first else point, 70.0, col, 0.35)
			Sfx.play_at("skill/thunder", point, objects)
			if first == null:
				return
			var struck: Array = [first]
			_spell_hit(first, float(sp["damage"]), "energy", float(sp["stun"]))
			var last: Node2D = first
			for _i in int(sp["chains"]):
				var nxt: Node2D = null
				var nd: float = float(sp["chain_range"])
				for t in _foes(foe):
					if t in struck or t.get("dead") == true or not is_instance_valid(last):
						continue
					var dd: float = t.position.distance_to(last.position)
					if dd < nd:
						nxt = t
						nd = dd
				if nxt == null:
					break
				SkillFx.bolt(objects, nxt.position, col, last.position)
				_spell_hit(nxt, float(sp["damage"]) * 0.5, "energy", float(sp["stun"]) * 0.6)
				struck.append(nxt)
				last = nxt
			gain_xp(Skills.XP_SPELL * struck.size())
		"aegis":
			if pilot.dome != null and is_instance_valid(pilot.dome):
				pilot.dome.queue_free()
			var dome := SkillFx.Dome.new()
			dome.radius = float(sp["radius"])
			dome.color = col
			pilot.add_child(dome)
			pilot.dome = dome
			pilot.dome_hp = float(sp["soak"])
			pilot.dome_max = float(sp["soak"])
			pilot.dome_left = float(sp["time"])
			SkillFx.ring(objects, from, float(sp["radius"]) * 1.2, col, 0.45)
			for t in _foes(foe):
				var dd: float = t.position.distance_to(from)
				if t.get("dead") != true and dd < float(sp["radius"]):
					_spell_hit(t, float(sp["damage"]), "energy", 0.5)
					if is_instance_valid(t) and t.get("dead") != true:
						_shove(t, from.direction_to(t.position) * (float(sp["radius"]) - dd + 30.0))
			Sfx.play_at("skill/dome", from, objects)
		"eidola":
			var n: int = int(sp["count"])
			for i in n:
				var spot := _nearest_walkable(from + Vector2.from_angle(TAU * i / float(n) + 0.6) * Vector2(80.0, 46.0))
				var e: Node2D = PROPS.Eidolon.new()
				e.surface = self
				e.master = pilot
				e.home = spot
				e.position = spot
				e.life = float(sp["time"])
				e.damage = float(sp["damage"])
				objects.add_child(e)
				npcs.append(e)
				SkillFx.circle(objects, spot, 62.0, col, 1.1)
			Sfx.play_at("skill/summon", from, objects)


func _phlox_burst(at: Vector2, sp: Dictionary, aimed: Variant = null) -> void:
	var col: Color = SPELL_COLORS["phlox"]
	var rad := float(sp["radius"])
	SkillFx.ring(objects, at, rad, col, 0.45)
	SkillFx.burst(objects, at, rad, col)
	Sfx.play_at("skill/burst", at, objects)
	var n := 0
	for t in _foes(aimed):
		var d: float = t.position.distance_to(at)
		if t.get("dead") == true or d > rad:
			continue
		_spell_hit(t, float(sp["damage"]) * (1.0 - 0.4 * d / rad), "heat", 0.3)
		n += 1
		if is_instance_valid(t) and t.get("dead") != true:
			_burns.append({"node": t, "dps": float(sp["burn"]), "left": float(sp["burn_time"]), "t": 0.0})
	if n > 0:
		gain_xp(Skills.XP_SPELL * n)


## Experience (Skills): a level gained says so - a skill point to spend.
func gain_xp(n: int) -> void:
	var up := Skills.add_xp(state["player"], n)
	if up > 0 and pilot:
		var lv := Skills.level(state["player"])
		show_prompt("Level %d!  A skill point to spend - the Field Computer's SKILLS tab (K)." % lv, 4.5)
		Effects.float_text(pilot.global_position + Vector2(0, -150), "LEVEL %d" % lv, Color(1.0, 0.85, 0.4))
		SkillFx.ring(objects, pilot.position, 110.0, Color(1.0, 0.85, 0.4), 0.7)
		GameLog.post("The automaton reached level %d: a skill point to spend (Field Computer > SKILLS)." % lv, "good")
		Sfx.play_at("skill/levelup", pilot.position, objects)
	_update_hud()


## The move under way ends (done, or you were knocked out).
func _end_move() -> void:
	if pilot:
		pilot.airborne = false
		pilot.hop = 0.0
		pilot.busy = 0.0
		pilot.guard_left = 0.0
		if pilot.puppet and pilot.puppet.clip_mode:
			pilot.puppet.stop()
	if _move.get("kind", "") in ["blow", "comet"]:
		_combo_t = 0.0
	_move = {}


func _update_skills(delta: float) -> void:
	_combo_t += delta
	# What burns, what a beam still cuts through.
	for i in range(_beams.size() - 1, -1, -1):
		var b: Dictionary = _beams[i]
		b["t"] = float(b["t"]) - delta
		if float(b["t"]) > 0.0:
			continue
		b["t"] = 0.13
		b["left"] = int(b["left"]) - 1
		var n := 0
		for t in _foes(b.get("foe")):
			if t.get("dead") == true:
				continue
			var q := Geometry2D.get_closest_point_to_segment(t.position, b["a"], b["b"])
			if q.distance_to(t.position) < float(b["width"]):
				_spell_hit(t, float(b["damage"]), "energy", 0.15)
				n += 1
		if n > 0:
			gain_xp(Skills.XP_SPELL * n if int(b["left"]) == 0 else 0)
		if int(b["left"]) <= 0:
			_beams.remove_at(i)
	for i in range(_burns.size() - 1, -1, -1):
		var f: Dictionary = _burns[i]
		var t = f["node"]
		f["left"] = float(f["left"]) - delta
		f["t"] = float(f["t"]) + delta
		if not is_instance_valid(t) or t.get("dead") == true or float(f["left"]) <= 0.0:
			_burns.remove_at(i)
			continue
		if float(f["t"]) >= 0.5:
			f["t"] = 0.0
			_spell_hit(t, float(f["dps"]) * 0.5, "heat")
			if is_instance_valid(t):
				SkillFx.impact(objects, t.position + Vector2(randf_range(-14, 14), -30 - randf() * 40.0), SPELL_COLORS["phlox"], 0.5)
	if _move.is_empty() or pilot == null:
		return
	var mv := _move
	mv["t"] = float(mv["t"]) + delta
	var t: float = mv["t"]
	match str(mv["kind"]):
		"blow":
			if not mv["done"] and t >= float(mv["at"]):
				mv["done"] = true
				_land_blow(mv)
		"cast":
			if not mv["done"] and t >= float(mv["at"]):
				mv["done"] = true
				_cast_now(mv)
		"leap", "comet":
			var off: float = mv["off"]
			var land: float = mv["land"]
			var arrive: float = mv["at"] if mv["kind"] == "comet" else land
			var u := clampf((t - off) / maxf(0.01, arrive - off), 0.0, 1.0)
			var from: Vector2 = mv["from"]
			var to: Vector2 = mv["to"]
			pilot.position = from.lerp(to, u * u * (3.0 - 2.0 * u))
			var up := clampf((t - off) / maxf(0.01, land - off), 0.0, 1.0)
			pilot.airborne = t >= off and t < land
			pilot.hop = sin(up * PI) * (16.0 + from.distance_to(to) * 0.1) if pilot.airborne else 0.0
			if mv["kind"] == "comet" and not mv["done"] and t >= float(mv["at"]):
				mv["done"] = true
				_land_blow(mv)
			if t >= land and not mv.get("landed", false):
				mv["landed"] = true
				SkillFx.ring(objects, pilot.position, 60.0, Color(0.9, 0.9, 0.8), 0.35)
				Sfx.play_at("skill/land", pilot.position, objects, -3.0)
				var shock := float(mv.get("shock", 0.0))
				if shock > 0.0:
					SkillFx.ring(objects, pilot.position, 105.0, Skills.school_color("leap"), 0.4)
					for h in _foes():
						if h.get("dead") != true and h.position.distance_to(pilot.position) < 100.0:
							_spell_hit(h, shock, "kinetic", 0.6)
	if t >= float(mv["time"]):
		_end_move()


## Loot lying about (LootDrop), taken when you walk over it.
var loot: Array = []
const LOOT_ITEMS := ["scrap", "energy_cell", "weapons", "data_core", "alien_alloy", "medicine", "energy_drink"]

## Can pirates aim at you? (Not while you're knocked out, upstairs or on the stairs.)
func pilot_targetable() -> bool:
	return pilot != null and pilot.hp > 0.0 and level == 0 and not _climbing


## Gear's chances (Gear): from a pirate, a big beast, a container.
const PIRATE_GEAR_CHANCE := 0.15
const BEAST_GEAR_CHANCE := 0.1
const CONTAINER_GEAR_CHANCE := {"chest": 0.2, "locker": 0.25, "vault": 0.6}

func _loot_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r


## A citizen or pirate fell: off the surface; a pirate drops loot.
func npc_died(n: Node2D) -> void:
	npcs.erase(n)
	if n.species == "pirate":
		var drop := PROPS.LootDrop.new()
		drop.position = n.position
		drop.contents = [["credits", randi_range(15, 60)]]
		if randf() < 0.6:
			drop.contents.append([LOOT_ITEMS.pick_random(), randi_range(1, 2)])
		if randf() < PIRATE_GEAR_CHANCE:   # (a piece of automaton gear - Gear)
			drop.contents.append([Gear.roll(_loot_rng(), "foot", 0.25), 1])
		objects.add_child(drop)
		loot.append(drop)
		Sfx.play_at("pirate/loot_drop", drop.position, objects, -2.0)
		GameLog.post("The pirate %s is down." % n.npc_name, "info")
		if n.last_hit_by == pilot and pilot != null:
			_regain_check()
			gain_xp(Skills.xp_for_kill(n.max_hp))
	elif n.species == "eidolon":
		pass
	else:
		GameLog.post("%s (%s) has fallen to the pirates." % [n.npc_name, n.role], "warning")


## An animal fell (SurfaceCreature): it stays gone until you land again.
func creature_died(c: Node2D) -> void:
	creatures.erase(c)
	if c.last_by == pilot and pilot != null:
		_regain_check()
		gain_xp(Skills.xp_for_kill(c.max_hp))
		var e: Dictionary = _bestiary_entry(c.species)
		e["kills"] = int(e.get("kills", 0)) + 1
	if not c.plan.is_empty():
		c.plan["dead"] = true
		c.plan["node"] = null
	if c.hostile:
		GameLog.post("The %s is down." % c.spec["name"], "info")
	# What's left of it: Cybernetic Matter, more from the bigger beasts - the
	# volcanic beasts only minerals (ore from their stone hides).
	var drop := PROPS.LootDrop.new()
	drop.position = c.position if _ground_ok(c.position) else _nearest_walkable(c.position)
	if c.set_id == "vo":
		drop.contents = volcanic_ore(c.max_hp, hash(str(c.plan.get("pos", c.position))))
		drop.label = "Minerals"
		drop.light = Color(1.0, 0.6, 0.2, 0.9)
	else:
		drop.contents = [["cyber_matter", clampi(roundi(c.max_hp / 20.0), 1, 8)]]
		drop.label = "Cybernetic matter"
		drop.light = Color(0.4, 1.0, 0.95, 0.9)
	# The big beasts now and then carry gear something left in them (Gear).
	if c.max_hp >= 120.0 and randf() < (BEAST_GEAR_CHANCE * 1.5 if c.set_id == "vo" else BEAST_GEAR_CHANCE):
		drop.contents.append([Gear.roll(_loot_rng(), "foot", clampf(c.max_hp / 600.0, 0.2, 0.8)), 1])
	objects.add_child(drop)
	loot.append(drop)


## What a volcanic beast leaves (minerals only): iron ore always, titanium
## from the tougher ones, platinum now and then from the biggest - more the
## bigger it was.
static func volcanic_ore(hp: float, seed_: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var out := [["iron_ore", clampi(roundi(hp / 40.0), 1, 8)]]
	if hp >= 100.0:
		out.append(["titanium_ore", clampi(roundi(hp / 80.0), 1, 4)])
	if hp >= 200.0 and rng.randf() < 0.6:
		out.append(["platinum_ore", rng.randi_range(1, 2)])
	return out


## Takes the loot you're standing on.
func _collect_loot() -> void:
	for d in loot.duplicate():
		if not is_instance_valid(d):
			loot.erase(d)
		elif pilot.position.distance_to(d.position) < 60.0 and level == 0:
			var left := []
			for c in d.contents:
				var rest := _give(c[0], int(c[1]))
				if rest > 0:
					left.append([c[0], rest])
			if left.size() == d.contents.size() and left == d.contents:
				continue   # (nothing fitted: it stays where it lies)
			Sfx.play("pirate/loot_take")
			if left.is_empty():
				loot.erase(d)
				d.queue_free()
			else:
				d.contents = left   # (what your full pack couldn't take stays on the ground)


## Your health ran out: you come to beside your ship, the pirates having
## helped themselves to a tenth of your credits. What you've explored stays
## explored (the fog of war is kept - and stored with the planet now).
## Who last bit you (SurfaceCreature: an animal's name) and when (ms): an
## animal knocking you out takes no credits.
var bitten_by := ""
var bitten_at := -99999
var bitten_by_node: Node2D          # (and which: you fire back at it, _fire_back)

func knocked_out() -> void:
	_store_fog()
	var player: Dictionary = state["player"]
	var beast := bitten_by if Time.get_ticks_msec() - bitten_at < 1500 else ""
	var lost := 0 if beast != "" else int(int(player.get("credits", 0)) * 0.1)
	player["credits"] = int(player.get("credits", 0)) - lost
	var gone := LostItems.lose_one(player, -1.0, "carried")   # (and one thing you carried - kills may win it back)
	stop_attack()
	_end_move()
	pilot.path = PackedVector2Array()
	pilot.moving = false
	_far_goal = Vector2.INF
	_target_thing = null
	_holding = false
	if level == 1:
		_set_level(0, null)
	pilot.position = lander.position + Vector2(0, 90)
	ground_force = true
	pilot.hp = pilot.max_hp
	pilot.stamina = maxf(pilot.stamina, Stamina.LOW)   # (back on your feet, a little rested)
	_update_hud()
	if beast != "":
		GameLog.post("Brought down by a %s! You come to beside your ship." % beast, "warning")
		show_prompt("You were knocked out by a %s." % beast, 4.0)
	else:
		GameLog.post("Knocked out by pirates! You come to beside your ship - %d drachmas gone." % lost, "warning")
		show_prompt("You were knocked out - the pirates took %d drachmas." % lost, 4.0)
	if gone != "":
		GameLog.post("Lost: %s. Defeating enemies may recover it." % gone, "warning")
	for c in pilot.get_children():
		if c is Camera2D:
			c.reset_smoothing()
	_update_hud()


## A kill of yours (a pirate, an animal): a chance to win back something you
## lost (LostItems) - "ITEM REGAINED" on screen.
func _regain_check() -> void:
	var got := LostItems.regain(state["player"])
	if got != "":
		RegainPopup.show_item(get_tree(), got)
		GameLog.post("Item regained: %s." % got, "mission")
		_update_hud()


## A walkable spot at or near `p` (spiral search, up to ~5 tiles).
func _nearest_walkable(p: Vector2) -> Vector2:
	if walkable_at(p, 8.0):
		return p
	for r in range(1, 12):
		for k in 12:
			var q := p + Vector2.from_angle(k * TAU / 12.0) * r * 40.0
			if walkable_at(q, 8.0):
				return q
	return p


## Every building's footprint, built or still only planned (maps).
func building_rects() -> Array:
	var out := []
	for b in buildings:
		out.append(b.rect)
	for p in _plans:
		if p["built"] == null:
			out.append(_plan_rect(p))
	return out


func _thing_at(world: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	var things: Array = [lander] + npcs   # (animals aren't here: they're fired at, _hostile_at)
	if is_instance_valid(quest_giver):
		things.append(quest_giver)
	for b in buildings:   # chests, lockers and vaults (ground floor)
		if level == 0 and b.bounds.grow(60).has_point(world):
			for f in b.furniture:
				if f.is_container():
					things.append(f)
	for b in buildings:
		if b.upper != null:
			things.append(b.upper.up_thing)
	for g in gates:
		if g["node"] != null:
			things.append(g["node"])
	if level == 1:   # upstairs: the way down, and the containers up here
		things = [level_b.upper.down_thing]
		var upstairs = level_b.upper.get("furniture")   # (absent on floors built before a hot reload)
		for f in upstairs if upstairs is Array else []:
			if f.is_container():
				things.append(f)
	for t in things:
		var d := world.distance_to(t.click_center() - Vector2(0, lift_at(t.global_position)))   # (as drawn)
		if d < t.click_radius and d < best_d:
			best = t
			best_d = d
	return best


## A destination beyond the path grid's window (the planet map): walked to
## leg by leg, each leg to the window's edge toward it.
var _far_goal := Vector2.INF
var _far_origin := Vector2i(-1, -1)
var _far_from := Vector2.ZERO

func _walk_to(world: Vector2) -> void:
	_far_goal = Vector2.INF
	if level == 0 and _astar != null and not in_nav(world, 3):
		_far_goal = world
		_far_origin = _nav_origin
		_far_from = pilot.position
		# The last point toward it still well inside the window.
		var a := pilot.position
		var leg := a
		for k in range(1, 65):
			var p := a.lerp(world, k / 64.0)
			if not in_nav(p, 8):
				break
			leg = p
		world = _nearest_walkable(leg)
	pilot.path = _p_path(pilot.position, world)
	pilot.target = pilot.path[-1] if not pilot.path.is_empty() else pilot.position
	pilot.moving = not pilot.path.is_empty()
	# The way there leaves the path grid's window (a long way round): it takes
	# you as near as it can; once the window has moved on with you, on again.
	if level == 0 and _far_goal == Vector2.INF and pilot.moving and pilot.path[-1].distance_to(world) > 24.0:
		_far_goal = world
		_far_origin = _nav_origin
		_far_from = pilot.position


# --- Navigation ----------------------------------------------------------------------

## The path-finding grid covers a NAV_WIN x NAV_WIN tile window around you
## (NAV_S points per tile): built on a worker thread from a snapshot of the
## buildings there, then swapped in. It follows you (re-centred when you're
## NAV_SHIFT tiles off its centre) and is rebuilt when a building appears in it.
var _nav_origin := Vector2i.ZERO    # the window's first tile
var _nav_task := -1                # the running stage's task (or group task)
var _nav_stage := 0
var _nav_job := {}
var _nav_lock := Mutex.new()
var _nav_box := {}
var _nav_dirty := false

func _nav_window(origin := _nav_origin) -> Rect2i:
	return Rect2i(origin, Vector2i(NAV_WIN, NAV_WIN))


func _nav_origin_for(cell: Vector2i) -> Vector2i:
	return (cell - Vector2i(NAV_WIN / 2, NAV_WIN / 2)).clamp(Vector2i.ZERO, Vector2i(N - NAV_WIN, N - NAV_WIN))


## Rebuilds the grid around you now (awaitable).
func _build_nav() -> void:
	while _nav_task >= 0:   # (one at a time)
		await get_tree().process_frame
		_poll_nav()
	_start_nav()
	while _nav_task >= 0:
		await get_tree().process_frame
		_poll_nav()


func _start_nav() -> void:
	var origin := _nav_origin_for(_cell_at(pilot.position if pilot else _cell_pos(Vector2i(N / 2, N / 2))))
	var area := Rect2(_cell_pos(origin), Vector2.ZERO).expand(_cell_pos(origin + Vector2i(NAV_WIN, 0))) \
		.expand(_cell_pos(origin + Vector2i(0, NAV_WIN))).expand(_cell_pos(origin + Vector2i(NAV_WIN, NAV_WIN))).grow(200)
	var bs := buildings.filter(func(b): return area.intersects(b.bounds))
	_nav_dirty = false
	_nav_box = {}
	var n := NAV_WIN * NAV_S
	var k := 1.0 / NAV_S
	var xf := Transform2D(_g2w.x * k, _g2w.y * k, _g2w * (Vector2(origin) + Vector2(0.5 * k - 0.5, 0.5 * k - 0.5)))
	var idx := _snapshot_index(bs)
	var job := {"origin": origin, "bs": bs, "idx": idx, "xf": xf, "n": n, "rows": [], "rows2": []}
	job["rows"].resize(n)
	job["rows2"].resize(n)
	_nav_job = job
	# 1: walkable points, rows in parallel.
	_nav_stage = 1
	_nav_task = WorkerThreadPool.add_group_task(func(a: int) -> void:
		var row := PackedByteArray()
		row.resize(n)
		for b in n:
			if not _walkable_snap(xf * Vector2(a, b), NAV_CLEAR, idx):
				row[b] = 1
		_nav_lock.lock()
		job["rows"][a] = row
		_nav_lock.unlock(), n, BgWork.threads(), false, "Surface paths")


## Advances the grid build; swaps in a finished grid.
func _poll_nav() -> void:
	if _nav_task < 0:
		return
	if _nav_stage == 3:
		if not WorkerThreadPool.is_task_completed(_nav_task):
			return
		WorkerThreadPool.wait_for_task_completion(_nav_task)
	else:
		if not WorkerThreadPool.is_group_task_completed(_nav_task):
			return
		WorkerThreadPool.wait_for_group_task_completion(_nav_task)
	var job := _nav_job
	var n: int = job["n"]
	var xf: Transform2D = job["xf"]
	match _nav_stage:
		1:   # 2: no stepping between two free points across water / a crevasse corner
			_nav_stage = 2
			var rows: Array = job["rows"]
			_nav_task = WorkerThreadPool.add_group_task(func(a: int) -> void:
				var row: PackedByteArray = rows[a].duplicate()
				var next: PackedByteArray = rows[a + 1] if a + 1 < n else PackedByteArray()
				for b in n:
					if row[b] == 1:
						continue
					var w := xf * Vector2(a, b)
					if a + 1 < n and next[b] == 0:
						var wq := xf * Vector2(a + 1, b)
						if not (_ground_ok(w.lerp(wq, 0.25)) and _ground_ok(w.lerp(wq, 0.5)) and _ground_ok(w.lerp(wq, 0.75))):
							row[b] = 1
							continue
					if b + 1 < n and rows[a][b + 1] == 0:
						var wq := xf * Vector2(a, b + 1)
						if not (_ground_ok(w.lerp(wq, 0.25)) and _ground_ok(w.lerp(wq, 0.5)) and _ground_ok(w.lerp(wq, 0.75))):
							row[b] = 1
				_nav_lock.lock()
				job["rows2"][a] = row
				_nav_lock.unlock(), n, BgWork.threads(), false, "Surface paths")
		2:   # 3: the grid itself, and the doorways
			_nav_stage = 3
			_nav_task = WorkerThreadPool.add_task(func() -> void: _nav_box = _make_nav(job), false, "Surface paths")
		3:
			_nav_task = -1
			_nav_stage = 0
			if not _nav_box.is_empty():
				_astar = _nav_box["astar"]
				_nav_from_grid = _nav_box["xf"]
				_nav_origin = _nav_box["origin"]
				_nav_comp = _nav_box["comp"]


## Keeps the window around you (call every frame).
func _stream_nav() -> void:
	_poll_nav()
	if _nav_task >= 0 or level != 0:
		return
	var here := _cell_at(pilot.position)
	var off := here - (_nav_origin + Vector2i(NAV_WIN / 2, NAV_WIN / 2))
	var want := _nav_origin_for(here)
	if _nav_dirty or (maxi(absi(off.x), absi(off.y)) > NAV_SHIFT and want != _nav_origin):
		_start_nav()


## The grid from a build job's solid rows, doorways opened (worker thread).
func _make_nav(job: Dictionary) -> Dictionary:
	var n: int = job["n"]
	var xf: Transform2D = job["xf"]
	var bs: Array = job["bs"]
	var origin: Vector2i = job["origin"]
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	var solid := PackedByteArray()   # (the same flags, flat: for the regions below)
	solid.resize(n * n)
	for a in n:
		var row: PackedByteArray = job["rows2"][a]
		for b in n:
			if row[b] == 1:
				astar.set_point_solid(Vector2i(a, b), true)
				solid[a * n + b] = 1
	# Every doorway gets a guaranteed lane of free points straight through it.
	var inv := xf.affine_inverse()
	for b in bs:
		for d in b.doors:
			var along: Vector2 = d.dir.normalized()
			var nrm := along.orthogonal()
			var length: float = d.dir.length()
			var lo := SurfaceTiles.DOOR.x * length + 1.5
			var hi := SurfaceTiles.DOOR.y * length - 1.5
			var g: Vector2 = inv * (d.start + d.dir * 0.5)
			var c := Vector2i(roundi(g.x), roundi(g.y))
			for dx in range(-4, 5):
				for dy in range(-4, 5):
					var q := c + Vector2i(dx, dy)
					if not astar.is_in_boundsv(q) or not astar.is_point_solid(q):
						continue
					var w := xf * Vector2(q)
					var t: float = (w - d.start).dot(along)
					if t > lo and t < hi and absf((w - d.start).dot(nrm)) < 16.0 and _walkable_snap(w, 5.0, job["idx"]):
						astar.set_point_solid(q, false)
						solid[q.x * n + q.y] = 0
	return {"astar": astar, "xf": xf, "origin": origin, "comp": _label_regions(solid, n)}


## Each free point's region (flood fill over the solid flags, n x n): a path
## between points of different regions doesn't exist, and is refused without
## a search (find_path). About 150,000 points: no allocations in the loop.
static func _label_regions(solid: PackedByteArray, n: int) -> PackedInt32Array:
	var comp := PackedInt32Array()
	comp.resize(n * n)
	comp.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(n * n)
	var regions := 0
	for start in n * n:
		if comp[start] >= 0 or solid[start] == 1:
			continue
		comp[start] = regions
		queue[0] = start
		var head := 0
		var tail := 1
		while head < tail:
			var c := queue[head]
			head += 1
			var ci := c / n
			var cj := c % n
			var q := c - n
			if ci > 0 and comp[q] < 0 and solid[q] == 0:
				comp[q] = regions
				queue[tail] = q
				tail += 1
			q = c + n
			if ci < n - 1 and comp[q] < 0 and solid[q] == 0:
				comp[q] = regions
				queue[tail] = q
				tail += 1
			q = c - 1
			if cj > 0 and comp[q] < 0 and solid[q] == 0:
				comp[q] = regions
				queue[tail] = q
				tail += 1
			q = c + 1
			if cj < n - 1 and comp[q] < 0 and solid[q] == 0:
				comp[q] = regions
				queue[tail] = q
				tail += 1
		regions += 1
	return comp



## Whole-map nav coordinates (NAV_S points per tile, unclamped, not tied to
## the window): the upper floors' own little grids use these.
func nav_xf_global() -> Transform2D:
	var k := 1.0 / NAV_S
	return Transform2D(_g2w.x * k, _g2w.y * k, _g2w * Vector2(0.5 * k - 0.5, 0.5 * k - 0.5))


func nav_point_global(world: Vector2) -> Vector2i:
	var g := nav_xf_global().affine_inverse() * world
	return Vector2i(roundi(g.x), roundi(g.y))


## True if `world` is inside the path grid's window (with `margin` tiles to spare).
func in_nav(world: Vector2, margin := 0) -> bool:
	return _nav_window().grow(-margin).has_point(_cell_at(world))


## Every sliding door on the surface.
func all_doors() -> Array:
	var out := []
	for b in buildings:
		out.append_array(b.doors)
	return out


## The door whose opening the move a -> b passes through (or null).
func door_on(a: Vector2, b: Vector2) -> Node2D:
	for d in all_doors():
		if Geometry2D.segment_intersects_segment(a, b, d.start, d.start + d.dir) != null:
			return d
	return null


## Cell level (worker thread): links every separate patch of walkable land
## (4+ tiles) to the landmass around the landing site with a sandbar, so
## everything can be walked to. True if any was carved.
func _connect_islands() -> bool:
	var comp := PackedInt32Array()
	comp.resize(N * N)
	comp.fill(-1)
	var walk := PackedByteArray()
	walk.resize(N * N)
	_walk_open(walk)
	var sizes := PackedInt32Array()
	var firsts := PackedInt32Array()      # a cell of each patch
	var queue := PackedInt32Array()
	queue.resize(N * N)
	for start in N * N:
		if comp[start] >= 0 or walk[start] == 0:
			continue
		var id := sizes.size()
		comp[start] = id
		queue[0] = start
		var head := 0
		var tail := 1
		while head < tail:
			var c := queue[head]
			head += 1
			var ci := c / N
			var cj := c % N
			if ci > 0 and comp[c - N] < 0 and walk[c - N] == 1:
				comp[c - N] = id; queue[tail] = c - N; tail += 1
			if ci < N - 1 and comp[c + N] < 0 and walk[c + N] == 1:
				comp[c + N] = id; queue[tail] = c + N; tail += 1
			if cj > 0 and comp[c - 1] < 0 and walk[c - 1] == 1:
				comp[c - 1] = id; queue[tail] = c - 1; tail += 1
			if cj < N - 1 and comp[c + 1] < 0 and walk[c + 1] == 1:
				comp[c + 1] = id; queue[tail] = c + 1; tail += 1
		sizes.append(tail)
		firsts.append(start)
	var center := Vector2i(N / 2, N / 2)
	var main_id: int = comp[center.x * N + center.y]
	if main_id < 0:
		return false
	var carved := false
	var near_main := PackedInt32Array()
	for id in sizes.size():
		if id == main_id:
			continue
		if sizes[id] < POCKET and _rock_pocket(comp, id, firsts[id]):
			continue
		if sizes[id] < 4:
			continue
		# The nearest bit of the main landmass (one sweep out from it, below).
		var c0 := Vector2i(firsts[id] / N, firsts[id] % N)
		if near_main.is_empty():
			near_main = _sweep_from(comp, main_id)
		var src: int = near_main[firsts[id]]
		if src < 0:
			continue
		var found := Vector2i(src / N, src % N)
		if Vector2(found).distance_to(Vector2(c0)) > MAX_CAUSEWAY:
			continue   # (too far to link: filled in with the rest that can't be reached - _fill_unreached)
		_carve_causeway(_cell_pos(found), _cell_pos(c0))
		carved = true
	return carved


## (worker thread) For every tile, the nearest tile of patch `id` (a
## breadth-first sweep out from all of it at once, over anything): -1 if none.
func _sweep_from(comp: PackedInt32Array, id: int) -> PackedInt32Array:
	var src := PackedInt32Array()
	src.resize(N * N)
	src.fill(-1)
	var queue := PackedInt32Array()
	for k in N * N:
		if comp[k] == id:
			src[k] = k
			queue.append(k)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var i := c / N
		var j := c % N
		for q in [c - N if i > 0 else -1, c + N if i < N - 1 else -1, c - 1 if j > 0 else -1, c + 1 if j < N - 1 else -1]:
			if q >= 0 and src[q] < 0:
				src[q] = src[c]
				queue.append(q)
	return src


## (worker thread) Open ground for the reachability checks (1 per tile):
## walkable, no crag, and not on or beside a cliff - the path grid keeps
## clear of a wall by a point, so a gap a tile or two wide between cliffs
## is no way through.
func _walk_open(walk: PackedByteArray) -> void:
	var cliffs := _cliff.size() == N * N
	for k in N * N:
		var ok: bool = pdata["terrain"][_terrain[k]][2] and _rock[k] < 77
		if ok and cliffs:
			var i := k / N
			var j := k % N
			ok = _cliff[k] == 0 and (i == 0 or _cliff[k - N] == 0) and (i == N - 1 or _cliff[k + N] == 0) \
				and (j == 0 or _cliff[k - 1] == 0) and (j == N - 1 or _cliff[k + 1] == 0)
		walk[k] = 1 if ok else 0


## (worker thread) Ground nothing reaches from the landing site (by
## _walk_open), and not beside ground that is reached, is filled in with rock:
## no open ground you can never get to.
func _fill_unreached() -> void:
	var walk := PackedByteArray()
	walk.resize(N * N)
	_walk_open(walk)
	var seen := PackedByteArray()
	seen.resize(N * N)
	var start := (N / 2) * N + N / 2
	if walk[start] == 0:
		return
	var queue := PackedInt32Array([start])
	seen[start] = 1
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for q in [c - N, c + N, c - 1, c + 1]:
			if q >= 0 and q < N * N and (absi(q - c) == N or q / N == c / N) and seen[q] == 0 and walk[q] == 1:
				seen[q] = 1
				queue.append(q)
	for k in N * N:
		if seen[k] == 1 or not pdata["terrain"][_terrain[k]][2] or _solid(k) >= 90:
			continue
		var i := k / N
		var j := k % N
		if (i > 0 and seen[k - N] == 1) or (i < N - 1 and seen[k + N] == 1) or (j > 0 and seen[k - 1] == 1) or (j < N - 1 and seen[k + 1] == 1):
			continue
		_rock[k] = 255


## A cut-off patch further than this (tiles) from the main land isn't linked.
const MAX_CAUSEWAY := 60.0

## Patches of ground smaller than this hemmed in by crags become part of them.
const POCKET := 40


## (worker thread) If patch `id` (from `start`) touches a crag or cliff, fills
## it with rock (a nook in a crag, a ledge cut off by cliffs: no way in) - true then.
func _rock_pocket(comp: PackedInt32Array, id: int, start: int) -> bool:
	var cells := PackedInt32Array([start])
	var seen := {start: true}
	var touches := false
	var head := 0
	while head < cells.size():
		var c := cells[head]
		head += 1
		for d in [-N, N, -1, 1]:
			var q: int = c + d
			if q < 0 or q >= N * N or (absi(d) == 1 and q / N != c / N):
				continue
			if comp[q] == id and not seen.has(q):
				seen[q] = true
				cells.append(q)
			elif comp[q] != id and (_solid(q) >= 77 or (_cliff.size() == N * N and _cliff[c] != 0)):
				touches = true   # (a crag or cliff along its edge)
	if not touches:
		return false
	for c in cells:
		_rock[c] = 255
	return true


## Targets that must be reachable: the open land and doorways in the path
## grid's window, and the citizens there.
func _reach_targets() -> Array:
	var out := []
	var win := _nav_window().grow(-2)
	for i in range(win.position.x, win.end.x):
		for j in range(win.position.y, win.end.y):
			var c := Vector2i(i, j)
			if walkable_cell(c) and not _blocked_cells.has(c):
				var w := _cell_pos(c)
				if walkable_at(w, NAV_CLEAR):
					out.append(w)
	for a in npcs:
		if in_nav(a.position, 2):
			out.append(a.position)
	for z in _door_zones:
		if in_nav(z[0], 2):
			out.append(z[0])
	return out


## Nav points reachable from `start` (8-way, like the path finder).
func _flood(start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
			var q: Vector2i = p + d
			if not seen.has(q) and _astar.is_in_boundsv(q) and not _astar.is_point_solid(q):
				if d.x != 0 and d.y != 0 and (_astar.is_point_solid(Vector2i(p.x + d.x, p.y)) or _astar.is_point_solid(Vector2i(p.x, p.y + d.y))):
					continue
				seen[q] = true
				queue.append(q)
	return seen


## Raises the ground to walkable land along a line (2 cells wide).
func _carve_causeway(a: Vector2, b: Vector2) -> void:
	var thresholds: Array = pdata["thresholds"]
	var first_walk := 0
	while first_walk < pdata["terrain"].size() and not pdata["terrain"][first_walk][2]:
		first_walk += 1
	var land: float = (thresholds[first_walk - 1] if first_walk > 0 else -1.0) + 0.06
	var ga := _world_to_grid * a
	var gb := _world_to_grid * b
	var steps := maxi(1, ceili(ga.distance_to(gb) * 1.5))
	var last := Vector2i(-1, -1)
	for k in steps + 1:
		var g := ga.lerp(gb, float(k) / steps)
		if Vector2i(roundi(g.x), roundi(g.y)) == last:
			continue
		last = Vector2i(roundi(g.x), roundi(g.y))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var c := Vector2i(roundi(g.x) + dx, roundi(g.y) + dy)
				if c.x < 0 or c.y < 0 or c.x >= N or c.y >= N:
					continue
				var idx := c.x * N + c.y
				if _height[idx] < land:
					_height[idx] = land
		_clear_rock(Vector2i(roundi(g.x), roundi(g.y)), 0.0)   # (a pass through crags / a ramp up a cliff)


## Re-derives terrain types and the ground shader's height map from _height.
func _refresh_terrain(area := Rect2i(0, 0, N, N)) -> void:
	var thresholds: Array = pdata["thresholds"]
	var r := area.intersection(Rect2i(0, 0, N, N))
	for i in range(r.position.x, r.end.x):
		for j in range(r.position.y, r.end.y):
			var k := i * N + j
			var t := 0
			while t < thresholds.size() and _height[k] > thresholds[t]:
				t += 1
			_terrain[k] = t
			var v := (_height[k] + 1.0) * 0.5
			_elev[k] = TERRAIN.elevation(_height[k], _ramp[k], _crag[k] / 255.0, Vector2(i, j), N, _water_top, _site_h)
			_height_img.set_pixel(i, j, Color(v, _rock[k] / 255.0, _ramp[k], _crag[k] / 255.0))
	_height_tex.update(_height_img)
	if map_tex:
		_repaint_map(r)


func _nav_point(world: Vector2) -> Vector2i:
	var g := _nav_from_grid.affine_inverse() * world
	var n := NAV_WIN * NAV_S
	return Vector2i(clampi(roundi(g.x), 0, n - 1), clampi(roundi(g.y), 0, n - 1))


## Nearest non-solid nav point (spiral search).
func _nearest_free(p: Vector2i) -> Vector2i:
	if not _astar.is_point_solid(p):
		return p
	for r in range(1, 14):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := p + Vector2i(dx, dy)
				if _astar.is_in_boundsv(q) and not _astar.is_point_solid(q):
					var d := Vector2(dx, dy).length()
					if d < best_d:
						best_d = d
						best = q
		if best.x >= 0:
			return best
	return p


## A walkable route from `from` to `to` (world points), going around walls
## and through doorways, straightened. If `to` can't be reached, ends at the
## closest reachable point.
## A route from `from` to `to` (waypoints), as far as it goes. `partial`: a
## route as near as possible when there's none (a click on water); the
## creatures pass false - a target in another region of the grid is refused
## at once, instead of a search over the whole grid (tens of ms).
func find_path(from: Vector2, to: Vector2, partial := true) -> PackedVector2Array:
	if _astar == null or not in_nav(from) or not in_nav(to):
		return PackedVector2Array([to])   # (outside the grid's window: walk straight, stop if blocked)
	if _segment_clear(from, to):
		return PackedVector2Array([to])
	var a := _nearest_free(_nav_point(from))
	var b := _nearest_free(_nav_point(to))
	if not partial and _nav_comp.size() == NAV_WIN * NAV_S * NAV_WIN * NAV_S:
		var n := NAV_WIN * NAV_S
		if _nav_comp[a.x * n + a.y] != _nav_comp[b.x * n + b.y]:
			return PackedVector2Array()
	var t0 := Time.get_ticks_usec()
	var ids := _astar.get_id_path(a, b, partial)
	path_calls += 1
	path_us += Time.get_ticks_usec() - t0
	if ids.is_empty():
		return PackedVector2Array()
	var pts := PackedVector2Array()
	for id in ids:
		pts.append(_nav_from_grid * Vector2(id))
	# The exact click point if it's walkable and we reached its nav point.
	if ids[-1] == b and walkable_at(to) and _segment_clear(pts[-1], to, 6.0):
		pts.append(to)
	# String-pulling: skip waypoints we can walk past in a straight line.
	# Candidates come from a cheap line-of-sight walk over the nav grid (its
	# solid points already encode walls, water and clearance); only the legs
	# chosen get the precise check.
	var cells: Array = Array(ids)
	if pts.size() > cells.size():
		cells.append(_nav_point(to))
	var out := PackedVector2Array()
	var cur := from
	var cur_cell := _nav_point(from)
	var i := 0
	while i < pts.size():
		var j := i
		while j + 1 < pts.size() and _grid_los(cur_cell, cells[j + 1]):
			j += 1
		while j > i and not _segment_clear(cur, pts[j]):
			j -= 1
		out.append(pts[j])
		cur = pts[j]
		cur_cell = cells[j]
		i = j + 1
	return out


## Line of sight between two nav points over free grid points (conservative:
## near-misses of solid points count as blocked).
func _grid_los(a: Vector2i, b: Vector2i) -> bool:
	var d := Vector2(b - a)
	var steps := maxi(1, int(maxf(absf(d.x), absf(d.y)) * 2.0))
	for k in steps + 1:
		var p := Vector2(a) + d * (float(k) / steps)
		var x0 := floori(p.x)
		var y0 := floori(p.y)
		var fx := p.x - x0
		var fy := p.y - y0
		var xs := [x0] if fx < 0.2 else ([x0 + 1] if fx > 0.8 else [x0, x0 + 1])
		var ys := [y0] if fy < 0.2 else ([y0 + 1] if fy > 0.8 else [y0, y0 + 1])
		for x in xs:
			for y in ys:
				var c := Vector2i(x, y)
				if not _astar.is_in_boundsv(c) or _astar.is_point_solid(c):
					return false
	return true


## Blocked head-on: slide along the obstacle (walls run diagonally on the
## isometric grid, so try angled steps, nearest to the wanted direction first).
func _slide(step: Vector2) -> bool:
	for ang in [0.45, -0.45, 0.9, -0.9, 1.25, -1.25]:
		var st := step.rotated(ang) * cos(ang)
		if st.length() > 0.05 and _p_walkable(pilot.position + st):
			pilot.position += st
			return true
	return false


# --- Floors: the pilot on the ground or upstairs (see BuildingFloors) -------------

## The ground-plane point under a clicked screen point (upstairs, the floor
## is drawn one storey up).
func _floor_point(world: Vector2) -> Vector2:
	return world + Vector2(0, BuildingFloors.LIFT) if level == 1 else world


func _p_walkable(p: Vector2, clear := 6.0) -> bool:
	return walkable_at(p, clear) if level == 0 else BuildingFloors.walkable(self, level_b, p, clear)


func _p_clear(a: Vector2, b: Vector2, clear := 9.0) -> bool:
	return _segment_clear(a, b, clear) if level == 0 else BuildingFloors.clear_line(self, level_b, a, b, clear)


func _p_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	return find_path(a, b) if level == 0 else BuildingFloors.path(self, level_b, a, b)


## Where a click (world point under the cursor) leads: [ground-plane point,
## floor (0 / 1), building]. Upstairs, a click on this floor stays on it;
## otherwise it's on the ground. From outside a building (its roof showing),
## a click on its roof goes to its upper floor.
func _click_target(world: Vector2) -> Array:
	var up_pt := world + Vector2(0, BuildingFloors.LIFT)
	if level == 1 and BuildingFloors.walkable(self, level_b, up_pt, 4.0):
		return [up_pt, 1, level_b]
	# A visible roof means you're outside that building: clicking it means upstairs.
	var ucell := tilemap.local_to_map(up_pt)
	for b in buildings:
		if b.upper != null and b.roof.modulate.a > 0.5 and b.rect.has_point(ucell) and BuildingFloors.walkable(self, b, up_pt, 4.0):
			return [up_pt, 1, b]
	return [world, 0, null]


## Walks to a destination on any floor, taking stairs on the way: down from
## this upper floor first if needed, then up the destination building's
## stairs (each climb resumes the route when it's done).
func _route_to(dest: Array) -> void:
	var lv: int = dest[1]
	var b: BuiltBuilding = dest[2]
	if lv == level and (lv == 0 or b == level_b):
		_walk_to(dest[0])
		return
	_pending_target = dest
	if level == 1:
		_target_thing = level_b.upper.down_thing    # down first
		_walk_to(level_b.upper.down_thing.approach())
	else:
		_target_thing = b.upper.up_thing
		_walk_to(b.upper.up_thing.approach())


## Climbs b's stairs (up = true) or goes down them: the pilot walks the
## flight, rising one storey (or sinking back) step by step.
func climb(b: BuiltBuilding, up: bool) -> void:
	if _climbing or b.upper == null:
		return
	_climbing = true
	_holding = false
	_target_thing = null
	pilot.path = PackedVector2Array()
	var f = b.upper
	var a: Vector2 = _cell_pos(f.stair_a)
	var t: Vector2 = _cell_pos(f.landing)
	var from := a if up else t
	var to := t if up else a
	if up:
		f.node.visible = true
		pilot.z_index = 3   # above the upper floor
	var tw := create_tween()
	tw.tween_method(func(u: float):
		pilot.position = from.lerp(to, u)
		# The steps span the middle two of the three tiles walked.
		var climbed := clampf((u * 3.0 - 0.5) / 2.0, 0.0, 1.0)
		pilot.lift = BuildingFloors.LIFT * (climbed if up else 1.0 - climbed)
		pilot.facing = 1.0 if to.x >= from.x else -1.0
		pilot.moving = true, 0.0, 1.0, 1.5)
	await tw.finished
	pilot.moving = false
	_set_level(1 if up else 0, b if up else null)
	_climbing = false
	# On the way somewhere: carry on (maybe up another building's stairs).
	if not _pending_target.is_empty():
		var dest := _pending_target
		_pending_target = []
		_route_to(dest)


func _set_level(lv: int, b: BuiltBuilding) -> void:
	if level_b != null and level_b.upper != null and level_b != b:
		level_b.upper.node.visible = false
	level = lv
	level_b = b
	pilot.lift = BuildingFloors.LIFT if lv == 1 else 0.0
	pilot.z_index = 3 if lv == 1 else 0
	if b != null:
		b.upper.node.visible = true
	GameLog.post("Upstairs in the %s." % b.title.to_lower() if lv == 1 else "Back on the ground floor.", "info")


## True if a straight walk between two points stays on walkable ground,
## with a little more clearance than the walker needs (no corner clipping).
## A clear line of fire between two ground points: no building wall across it
## (doorways are gaps in the walls) and no crag or cliff - NPCs only shoot
## along one, and bolts and arrows stop where one ends (SurfaceProps).
func shot_clear(a: Vector2, b: Vector2) -> bool:
	var box := Rect2(a, Vector2.ZERO).expand(b)
	for bld in buildings:
		if not bld.bounds.intersects(box, true):
			continue
		for seg in bld.segments:
			if Geometry2D.segment_intersects_segment(a, b, seg[0], seg[1]) != null:
				return false
	if _rock.size() == N * N:
		var steps := maxi(1, ceili(a.distance_to(b) / 24.0))
		for k in range(1, steps):
			if TERRAIN.rock_interp(_rock, N, _world_to_grid * a.lerp(b, float(k) / steps)) >= TERRAIN.ROCK_SOLID:
				return false
	return true


func _segment_clear(a: Vector2, b: Vector2, clear := 9.0, step := 5.0) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / step))   # (animals look 8 px apart: a wall's band is 12)
	for k in range(1, steps + 1):
		if not walkable_at(a.lerp(b, float(k) / steps), clear):
			return false
	return true


## Animals asleep (off the screen: SurfaceCreature._sleepy) - an eighth of them
## think each frame, with the time since their last turn.
var sleepers: Array = []
var clock := 0.0
var _sleep_i := 0
const SLEEP_SLICES := 8

func _tick_sleepers(delta: float) -> void:
	clock += delta
	if sleepers.is_empty():
		return
	var n := ceili(sleepers.size() / float(SLEEP_SLICES))
	for k in n:
		if sleepers.is_empty():
			break
		if _sleep_i >= sleepers.size():
			_sleep_i = 0
		var c = sleepers[_sleep_i]
		if is_instance_valid(c) and c.is_inside_tree() and c.sleep_tick(clock):
			_sleep_i += 1
		else:
			if is_instance_valid(c):
				c.listed = false
			sleepers.remove_at(_sleep_i)   # (awake, dead or gone)


## Far culling: what's well off screen is put on FAR_LAYER, which the
## viewport doesn't draw - Godot then skips it when it gathers and sorts what
## to draw (thousands of y-sorted pieces a frame: ~0.4 ms). Every CULL_EVERY
## frames. Still things (scenery, a building's walls / floors / roofs,
## furniture) piece by piece, by CULL_CELL squares of the ground: each square's
## pieces change layer only as the square comes into or goes out of view.
## Moving things (animals, people) by where they are.
const FAR_LAYER := 1 << 18
const CULL_MARGIN := 450.0
const CULL_EVERY := 6   # (older: frames between; now CULL_HZ, by time)
const CULL_HZ := 20.0
const CULL_FILE_US := 2000
var _cull_at := 0
const CULL_CELL := 512.0
const _DOOR_SCRIPT := preload("res://scripts/sliding_door.gd")
var _cull_k := 0
var _cull_cells := {}       # Vector2i -> [CanvasItem] (still pieces)
var _cull_shown := {}       # cells drawn now
var _culled_seen := {}      # objects' children already filed (instance id)

func _cull_far() -> void:
	# (CULL_HZ times a second - by time: every few frames was hundreds a second at 600 FPS)
	var now_us := Time.get_ticks_usec()
	if now_us - _cull_at < int(1e6 / CULL_HZ) or objects == null or not view_rect.has_area():
		return
	_cull_at = now_us
	var vp := get_viewport()
	if vp.canvas_cull_mask & FAR_LAYER:
		vp.canvas_cull_mask = vp.canvas_cull_mask & ~FAR_LAYER
	var vr := view_rect.grow(CULL_MARGIN)
	var filing := true
	for o in objects.get_children():
		var c := o as CanvasItem
		if c == null or c == pilot:
			continue
		if c.get_script() == null or c is Furniture or c is TeleportGate or c.get_script() == _DOOR_SCRIPT:
			var id := c.get_instance_id()
			# (Filing takes time - a landing's first pass, every piece of the
			# surface new: 7 ms at once - so a couple of ms a pass; what waits
			# is simply still drawn.)
			if filing and not _culled_seen.has(id) and Time.get_ticks_usec() - now_us > CULL_FILE_US:
				filing = false
			if filing and not _culled_seen.has(id):   # (newly placed: its pieces filed, hidden until their square shows)
				if _culled_seen.size() > 50000:
					_culled_seen.clear()   # (ids of long-gone things; re-filing one is harmless)
				_culled_seen[id] = true
				for d in [c] + c.find_children("*", "CanvasItem", true, false):
					var ci := d as CanvasItem
					# Leaves only: culling a parent hides all under it (a building's
					# holder could be off screen while its walls aren't).
					if ci is Node2D and not ci.get_children().any(func(x): return x is CanvasItem):
						var k := Vector2i(((ci as Node2D).global_position / CULL_CELL).floor())
						if not _cull_cells.has(k):
							_cull_cells[k] = []
						_cull_cells[k].append(ci)
						ci.visibility_layer = 1 if _cull_shown.has(k) else FAR_LAYER
			continue
		var want := 1 if vr.has_point(c.global_position) else FAR_LAYER
		if c.visibility_layer != want:
			c.visibility_layer = want
	# The squares in view now: show the new ones, hide the ones gone.
	var now := {}
	var lo := Vector2i((vr.position / CULL_CELL).floor())
	var hi := Vector2i((vr.end / CULL_CELL).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			now[Vector2i(x, y)] = true
	for k in now:
		if not _cull_shown.has(k):
			_cull_layer(k, 1)
	for k in _cull_shown:
		if not now.has(k):
			_cull_layer(k, FAR_LAYER)
	_cull_shown = now


func _cull_layer(k: Vector2i, layer: int) -> void:
	var list: Array = _cull_cells.get(k, [])
	var alive := []
	for ci in list:
		if is_instance_valid(ci):
			ci.visibility_layer = layer
			alive.append(ci)
	if alive.size() != list.size():
		_cull_cells[k] = alive


var _occl_k := 0
var _occl_dt := 0.0


## Built ahead, now landed on: the game as it is now (what you bought or found
## since it began building - your ship, your gear).
func adopt_state(new_state: Dictionary) -> void:
	var planets: Dictionary = state.get("planets", {})
	state = new_state
	if not state.has("planets"):
		state["planets"] = planets
	if not state["planets"].has(planet_id):
		state["planets"][planet_id] = planets.get(planet_id, {})
	background = false
	if lander:
		var pl: Dictionary = state.get("player", {})
		var cls := str(pl.get("ship_class", "player"))
		var look: Dictionary = pl.get("ship_look", {})
		if cls != lander.ship_class or look != lander.look:   # (another ship or paint since: its picture again)
			lander.ship_class = cls
			lander.look = look
			for c in lander.get_children():
				c.queue_free()
			lander._ready()
	refresh_gear()


## Your stats on foot from your loadout (Gear) and this planet's environment -
## again whenever the loadout changes (the Field Computer, the Ship Computer).
func refresh_gear() -> void:
	if pilot:
		pilot.apply_gear(state["player"], Planets.environment(planet_id))
		if _hud:
			_update_health()


## What's on screen (ground plane, a margin round it): SurfaceCreature
## updates the animals out of it at half rate.
var view_rect := Rect2()
## Frames since the world was shown (show_world) - the first UNVEIL_MAX render
## the ground faster, under the fade.
var _unveil_frames := 999
const UNVEIL_MAX := 30


## The ground in view all rendered (the landing's fade can lift) - or it's had time enough.
func world_settled() -> bool:
	if ground3d:
		return _unveil_frames >= UNVEIL_MAX or ground3d.pending() == 0
	return ground_chunks == null or _unveil_frames >= UNVEIL_MAX or ground_chunks.settled(get_canvas_transform().affine_inverse() * get_viewport_rect())

var _atlas_seen := 0   # (TerrainTiles.atlas_serial as of the ground's pictures)

func _process(delta: float) -> void:
	view_rect = (get_canvas_transform().affine_inverse() * get_viewport_rect()).grow(250.0)
	_tick_sleepers(delta)
	if ground_chunks and _atlas_seen != TTILES.atlas_serial:
		_atlas_seen = TTILES.atlas_serial   # (a ground atlas took its real pictures: drawn again)
		ground_chunks.refresh(Rect2(-1e7, -1e7, 2e7, 2e7))
	if ground3d:
		if _atlas_seen != TTILES.atlas_serial:
			_atlas_seen = TTILES.atlas_serial
			ground3d.redraw()
		ground3d.collect(6 if _unveil_frames < UNVEIL_MAX else Ground3D.MESHES_A_FRAME)   # (the chunks' meshes, as the workers finish them)
		if _unveil_frames < UNVEIL_MAX:
			_unveil_frames += 1
	if ground_chunks:
		var veiled := _unveil_frames < UNVEIL_MAX
		ground_chunks.update(view_rect, ground_force, 3 if veiled else GroundChunks.PER_FRAME)
		ground_force = false
		if veiled:
			_unveil_frames += 1
	_cull_far()
	_fog_t -= delta
	if _fog_t <= 0.0:
		_fog_t = 0.3
		reveal_around(pilot.position)
	# The world around you: scenery, buildings and citizens, the path grid
	# (none placed in the world's first two frames: they're long enough).
	_stream_chunks(0 if ground_chunks and _unveil_frames <= 2 else 3000)
	_stream_plans()
	creature_paths = 0
	_fauna_t -= delta
	if _fauna_t <= 0.0:
		_fauna_t = 0.5
		_stream_fauna()
	_stream_nav()
	_update_attack(delta)
	_update_tools(delta)
	_collect_loot()
	_update_health()
	if _far_goal != Vector2.INF and not pilot.moving and not _climbing and level == 0 and _nav_task < 0:
		if pilot.position.distance_to(_far_goal) < 12.0:
			_far_goal = Vector2.INF
		elif _nav_origin != _far_origin:
			_walk_to(_far_goal)   # (the window has moved on: the next leg)
		elif pilot.position.distance_to(_far_from) < 4.0:
			_far_goal = Vector2.INF   # (no way on)
		elif _nav_origin_for(_cell_at(pilot.position)) != _nav_origin:
			_nav_dirty = true     # (stopped short, the window not caught up: centre it on you)
		else:
			_far_goal = Vector2.INF   # (centred on you already: as near as it goes)
	var cam := get_viewport().get_camera_2d()
	if cam and not is_equal_approx(cam.zoom.x, _zoom):
		var z := lerpf(cam.zoom.x, _zoom, minf(1.0, delta * 12.0))
		cam.zoom = Vector2(z, z)
	# Gamepad: the left stick walks (toward a point a little ahead that way).
	var stick := Keybinds.stick_vector()
	if stick != Vector2.ZERO and not _climbing and not get_tree().paused and not (field_menu and field_menu.visible):
		_pad_walk = true
		_holding = false
		var goal := _floor_point(pilot.position + stick * 160.0)
		if _p_clear(pilot.position, goal):
			pilot.path = PackedVector2Array([goal])
		else:
			_repath_t -= delta
			if _repath_t <= 0.0:
				_repath_t = 0.25
				pilot.path = _p_path(pilot.position, goal)
		pilot.moving = not pilot.path.is_empty()
	elif _pad_walk:
		_pad_walk = false
		pilot.path = PackedVector2Array()
		pilot.moving = false
	# Hold the button to keep walking toward the cursor.
	if _holding and not _climbing:
		var cursor := get_canvas_transform().affine_inverse() * _last_mouse
		cursor = _floor_point(screen_to_ground(cursor) if level == 0 else cursor)
		_repath_t -= delta
		if _p_clear(pilot.position, cursor):
			pilot.path = PackedVector2Array([cursor])
		elif _repath_t <= 0.0:
			_repath_t = 0.25
			pilot.path = _p_path(pilot.position, cursor)
		pilot.moving = not pilot.path.is_empty()
	if pilot.moving and not _climbing and pilot.busy <= 0.0:
		# Next waypoint of the route.
		# Next waypoint once this one is reached - or nearly, if the way on is clear
		# from here (near door posts it must be hit exactly, or the next leg clips the post).
		while pilot.path.size() > 1 and (pilot.position.distance_to(pilot.path[0]) < 1.5
				or pilot.position.distance_to(pilot.path[0]) < 6.0 and _p_clear(pilot.position, pilot.path[1], 6.5)):
			pilot.path.remove_at(0)
		pilot.target = pilot.path[0] if not pilot.path.is_empty() else pilot.position
		var to: Vector2 = pilot.target - pilot.position
		if to.length() < 6.0 and pilot.path.size() <= 1:
			pilot.moving = false
			pilot.path = PackedVector2Array()
		else:
			var step: Vector2 = to.normalized() * minf(pilot.walk_speed() * delta, to.length())
			pilot.facing = 1.0 if step.x >= 0.0 else -1.0
			# A door ahead: ask it to open, and wait at it until it has.
			var door := door_on(pilot.position, pilot.position + to.normalized() * 16.0) if level == 0 else null
			if door != null:
				door.request_open()
			if door != null and door.open < 0.7:
				pass
			# Slide along obstacles (water, crevasses, map edge).
			elif _p_walkable(pilot.position + step):
				pilot.position += step
			elif _slide(step):
				pass
			else:
				# Blocked (e.g. clipped a corner): re-plan from here instead of stopping.
				var goal: Vector2 = pilot.path[-1] if not pilot.path.is_empty() else pilot.target
				pilot.path = _p_path(pilot.position, goal)
				pilot.moving = not pilot.path.is_empty() and pilot.position.distance_to(goal) > 8.0
	_occl_dt += delta
	if _occl_dt >= 1.0 / 60.0:   # (60 times a second, the time between added up: the fades look the same - by time, not frames: at 600 FPS every other frame was 300)
		_update_occlusion(_occl_dt)
		_occl_dt = 0.0
	# Reached the thing we clicked: interact.
	if _target_thing and not _climbing and pilot.position.distance_to(_ground_of(_target_thing)) < INTERACT_RANGE + 40.0 \
			and (not pilot.moving or pilot.position.distance_to(_ground_of(_target_thing)) < INTERACT_RANGE):
		var t := _target_thing
		_target_thing = null
		pilot.moving = false
		t.interact(self)


# --- Interactions ---------------------------------------------------------------------

## Adds loot to the space game snapshot (it's applied when you take off).
## Gives you something found here: credits, or an item into what you carry
## (Inventory: 12 slots, up to 100 of an item each) as far as it has room.
## What didn't fit (0: everything went in).
func _give(id: String, amount: int) -> int:
	var player: Dictionary = state["player"]
	if id == "credits":
		player["credits"] = int(player.get("credits", 0)) + amount
	else:
		var got := Inventory.add(carried(), id, amount, Inventory.PLAYER_SLOTS)
		if got <= 0:
			show_prompt("You can't carry any more (%d slots) - take things to your ship." % Inventory.PLAYER_SLOTS, 2.5)
			return amount
		Discovery.mark(get_tree(), "item:" + id)   # (the Encyclopedia)
		if got < amount:
			show_prompt("You can't carry any more (%d slots) - take things to your ship." % Inventory.PLAYER_SLOTS, 2.5)
		GameLog.loot(Items.display_name(id), got)
		Effects.float_text(pilot.global_position + Vector2(0, -70), "+%d %s" % [got, Items.display_name(id)], UI.GOLD)
		_update_hud()
		return amount - got
	GameLog.loot(Items.display_name(id), amount)
	Effects.float_text(pilot.global_position + Vector2(0, -70), "+%d %s" % [amount, Items.display_name(id)], UI.GOLD)
	_update_hud()
	return 0


## Clicking your ship: the transfer screen - what you carry and the ship's
## hold side by side (click a stack to move it across), and Take off.
func board_ship() -> void:
	var t := TransferPanel.new()
	t.surface = self
	add_child(t)


## Asks before taking off (clicking your ship, or the right-click menu).
func confirm_leave() -> void:
	UI.confirm(self, "Leave %s?" % pdata["name"], "Take off and return to orbit?", take_off, "Take off", "Stay")


func take_off() -> void:
	if SaveGame.travelling:
		return  # already taking off
	GameLog.post("Taking off from %s." % pdata["name"], "mission")
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_store_fog()
	SaveGame.pending = state
	SaveGame.took_off_from = planet_id
	SaveGame.landed_planet = ""
	SaveGame.travelling = true
	UI.fade_change_scene("res://main.tscn")


## The Esc menu's Save Game uses these: the space game, and where you are
## down here (`landed`: the planet, where you stand) - loading it brings you
## back to this spot (main.gd, SaveGame.resume).
func can_save() -> bool:
	return not AttractMode.active


func get_save_data() -> Dictionary:
	_store_fog()
	var d := state.duplicate()
	d["landed"] = {"planet": planet_id, "pos": [pilot.position.x, pilot.position.y] if pilot else []}
	return d


# --- HUD ----------------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.visible = not prebuilding
	add_child(_hud)

	var fx := Node2D.new()  # effects layer for floating texts
	fx.name = "FX"
	if not prebuilding:
		fx.add_to_group("fx_layer")   # (built ahead: joins once shown - space's effects aren't to land here)
	fx.z_index = 20
	add_child(fx)

	# Top-left: planet name, description, what you carry; under it the health gauge.
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	var ps := NeonTheme.box(Color(NeonTheme.CYAN, 0.6), Color(NeonTheme.BG, 0.82), 1, 8, 12)
	ps.accent = NeonTheme.CYAN
	ps.content_margin_left = 14
	ps.content_margin_right = 14
	ps.content_margin_top = 10
	ps.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", ps)
	_hud.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(UI.label(pdata["name"].to_upper(), 26, NeonTheme.HEAD))
	v.add_child(UI.label(pdata["desc"], 13, UI.TEXT_DIM))
	_credits_label = UI.label("", 15, UI.GOLD)
	v.add_child(_credits_label)
	# Health on foot: the automaton's outline filled red as high as its health,
	# in a blue ring filled as high as its shield, its afflictions round it
	# (HealthGauge - the same as the ship's in space).
	gauge = HealthGauge.new()
	gauge.which = "automaton"
	gauge.hull_name = "HEALTH"
	gauge.shield_name = "SHIELD"
	gauge.read = func(): return [pilot.hp, pilot.max_hp, pilot.shield, pilot.max_shield] if pilot else [1.0, 1.0, 0.0, 0.0]
	gauge.condition = func():
		var p: Dictionary = state["player"]
		if not p.get("condition") is Dictionary:
			p["condition"] = {}
		return p["condition"]
	gauge.shape_source = func(): return pilot.puppet._frame("idle", "s")["tex"] if pilot and pilot.puppet else null
	# The outer ring: stamina (Stamina), green, its rim red when it's low.
	gauge.fuel = func(): return [pilot.stamina, Stamina.MAX, Stamina.LOW] if pilot else [Stamina.MAX, Stamina.MAX, 0.0]
	gauge.fuel_name = "Stamina"
	gauge.fuel_liquid = Color(0.4, 0.95, 0.35)
	gauge.fuel_rim = Color(0.75, 1.0, 0.6)
	gauge.fuel_low_note = "  (tired: eat something)"
	gauge.tooltip_text = "Your stamina (the green ring): it runs down as you go, faster in a fight - eat food or drink an\nEnergy Drink (click it in the inventory, or put it on the toolbar); empty, you walk slowly and don't heal.\nYour shield (the blue ring) and health (the red inside). Pirates' bolts hit the shield first;\nit comes back quickly once you're out of the fight. Health comes back after a few calm seconds - not\nwhile a part of you is damaged (the icons round it). At 0 you're knocked out (back at your ship, minus 10% of your drachmas)."
	gauge.position = Vector2(16, 16)   # (on its own, no panel: just under the planet's panel)
	_hud.add_child(gauge)
	panel.resized.connect(func(): gauge.position = Vector2(16, panel.position.y + panel.size.y + 4))

	# Top-right: surface minimap.
	var mm := Control.new()
	mm.set_script(MINIMAP)
	mm.anchor_left = 1.0
	mm.anchor_right = 1.0
	mm.offset_left = -276
	mm.offset_right = -16
	mm.offset_top = 16
	mm.offset_bottom = 156
	mm.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud.add_child(mm)
	mm.setup(self)
	_minimap = mm
	# Map and level editor (right-click menu); below the Esc menu.
	var dev_layer := CanvasLayer.new()
	dev_layer.visible = not prebuilding
	dev_layer.layer = 6
	add_child(dev_layer)
	surface_map = SurfaceMap.new()
	surface_map.surface = self
	dev_layer.add_child(surface_map)
	field_menu = FIELD_MENU.new()
	field_menu.surface = self
	dev_layer.add_child(field_menu)
	MenuBackdrop.watch(field_menu, self)   # (the world as a picture behind it)
	# Bottom centre: the toolbar on foot.
	toolbar = SurfaceToolbar.new()
	toolbar.surface = self
	toolbar.anchor_left = 0.5
	toolbar.anchor_right = 0.5
	toolbar.anchor_top = 1.0
	toolbar.anchor_bottom = 1.0
	_hud.add_child(toolbar)
	var tw := toolbar.custom_minimum_size.x
	toolbar.offset_left = -tw * 0.5
	toolbar.offset_right = tw * 0.5
	toolbar.offset_top = -SurfaceToolbar.SLOT - 18
	toolbar.offset_bottom = -18
	level_editor = LevelEditor.new()
	level_editor.host = self
	dev_layer.add_child(level_editor)
	var tips := PinTips.install(self, "planets", EditorDocs.GAME)
	tips.f1_page = func() -> String:
		if level_editor.visible:
			return ""   # (the level editor opens its own documentation)
		if surface_map.visible or (field_menu.visible and field_menu.current == field_menu.MAP_TAB):
			return "surface-map"
		return "field-computer" if field_menu.visible else "planets"

	# Prompt line (what you're pointing at / what happened).
	_prompt = UI.label("", 18, Color.WHITE)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.offset_left = -600
	_prompt.offset_right = 600
	_prompt.offset_top = 20
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_child(_prompt)


	# Bottom-left: the event log (continues from space).
	var event_log := GameLog.new()
	_hud.add_child(event_log)

	UI.scale_fonts(_hud, "hud")
	# (as in space: grows with the text, stops short of the toolbar)
	var k := Settings.font_scale("hud")
	event_log.place(Vector2(440 * clampf(k, 1.0, 1.45), 220 * clampf(k, 1.0, 1.8)), toolbar)
	_update_hud()


var _health: ProgressBar
var damage_screen: DamageScreen
var gauge: HealthGauge

var _health_shown := -1.0

func _update_health() -> void:
	if _health and pilot:
		var k: float = pilot.hp / pilot.max_hp
		if k == _health_shown:
			return   # (setting the bar's colour redraws it: only when it changed)
		_health_shown = k
		_health.value = k * 100.0
		(_health.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(0.95, 0.3, 0.25).lerp(Color(0.35, 0.95, 0.5), k)


func _update_hud() -> void:
	var used := Inventory.slots_used(carried())
	_credits_label.text = "Carrying: %d / %d slots%s" % [used, Inventory.PLAYER_SLOTS,
		"  (full - take things to your ship)" if used >= Inventory.PLAYER_SLOTS else ""]


func show_prompt(text: String, hold := 3.0) -> void:
	_prompt.text = text
	_prompt.modulate.a = 1.0
	if _prompt_tween:
		_prompt_tween.kill()
	_prompt_tween = create_tween()
	_prompt_tween.tween_interval(hold)
	_prompt_tween.tween_property(_prompt, "modulate:a", 0.0, 0.5)
