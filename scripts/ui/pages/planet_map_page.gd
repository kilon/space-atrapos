class_name PlanetMapPage
extends VBoxContainer
## The Automaton's MAP > PLANET: a planet as a 3D globe (GlobeView, a
## Map3DView) - the one you're on, else the nearest (or one picked on the
## solar map: MapsPage.show_planet) - made from its real ground (PlanetShape:
## its heights, raised EXAG times, and colours - seas, shores, uplands, ice,
## lava; built on a worker the first time, kept), a grid every 30 degrees.
## Fog of war (PlanetFog - Galaxy.planet_fog): only the ground you've seen
## walking or flying low (CosmosMapMirror) shows; the rest is a dark haze,
## and what's in it is hidden. Marked where you've seen them: its towns, caves
## and dungeons, pirate camps; you (your heading), your ship.
## Drag to turn it, the wheel zooms (toward the cursor), a middle click (or
## Home) shows the whole world; click a mark for its details (the panel).
## A town you've walked into (Galaxy.town_visited) has its plan (TownPlan):
## zooming in over it, the globe closes in on it while the plan fades in over
## it - laid where the town is, the globe's north and scale, its names last -
## until it's all there (a click on it, or Town plan: the same dive, eased),
## and back out the same way. The plan shows the town from above - its
## buildings (CosmosTown's own layout, drawn on a worker), the square, the
## landing field and its points of interest named: the palace, the shrine,
## the storehouse, the field and, by a city's field, the ore buyer, the
## courier's office and the local pilot (CosmosSandbox.spots); you on it.
## The wheel zooms the plan on, dragging pans it; zooming out (or GLOBE) goes back.

const R := 100.0                 # the globe's radius (map units)
const EXAG := 3.0                # (the relief raised: a real world's is a few % of its radius)
const N := 72                    # quads a side of each of the cube's six faces
const PLAN_PPM := 3.0            # a town plan's pixels a metre
const KEEP := 6                  # globes (and plans) kept made
const PLAN_FROM := 3.0           # the plan starts showing at its fit zoom / this (and is all there at its fit)
const ANIM_S := 0.7              # (a click on a town: the dive onto it, s)
const TOWN_COL := Color(1.0, 0.82, 0.5)
const CAVE_COL := Color(0.75, 0.62, 1.0)
const CAMP_COL := Color(1.0, 0.35, 0.3)

var data: Node
var ship: Node2D
var world: Node                  # (the 3D game - Cosmos)
## The planet picked on the solar map (a CosmosPlanet) - else where you are.
var picked: Node = null
## Away from the 3D game (tests): the planet shown - {rec, shape, towns}.
var source := {}

static var _meshes := {}         # planet id -> ArrayMesh (the globe)
static var _tasks := {}          # planet id -> [task id, {mesh}]
static var _plans := {}          # town key -> ImageTexture (its plan)
static var _plan_tasks := {}     # town key -> [task id, {img}]
static var _roads := {}          # roads key (CosmosRoads.key_of) -> [[unit dirs (simplified), main]] (its roads on the globe)
static var _road_tasks := {}     # roads key -> [task id, {r}] (a world's network made for the map)
const ROAD_FILL := Color(0.86, 0.68, 0.42)    # (a main road's - city to city; a village's track paler, thinner)
const TRACK_FILL := Color(0.7, 0.6, 0.46)
const ROAD_CASE := Color(0.16, 0.11, 0.07)
const BRIDGE_CASE := Color(0.7, 0.66, 0.58)   # (a bridge's: its pale stone, under the road over the water)

## Every map being drawn collected (leaving the game: no task left in the pool).
static func finish_tasks() -> void:
	for k in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[k][0])
	_tasks = {}
	for k in _plan_tasks:
		WorkerThreadPool.wait_for_task_completion(_plan_tasks[k][0])
	_plan_tasks = {}
	for k in _road_tasks:
		WorkerThreadPool.wait_for_task_completion(_road_tasks[k][0])
	_road_tasks = {}

var _view: GlobeView
var _plan: TownPlan
var _title: Label
var _info: RichTextLabel
var _list: RichTextLabel
var _plan_btn: Button
var _look: Button
var _globe_btn: Button
var _list_sig := ""
var _t := {}                     # the planet shown (target())
var _follow_t := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_title = UI.label("PLANET MAP", 18, NeonTheme.HEAD)
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(_title)
	top.add_child(_legend(Color.WHITE, "You"))
	top.add_child(_legend(NeonTheme.INFO, "Your ship"))
	top.add_child(_legend(TOWN_COL, "Town"))
	top.add_child(_legend(CAVE_COL, "Cave / dungeon"))
	top.add_child(_legend(CAMP_COL, "Pirate camp"))
	_globe_btn = EditorIcons.dress(UI.button("GLOBE", close_plan, 14), "back", EditorIcons.tip("Back to the globe", "zoom out", "Leaves the town's plan for the whole world."))
	_globe_btn.focus_mode = FOCUS_NONE
	_globe_btn.visible = false
	top.add_child(_globe_btn)
	var fit := EditorIcons.dress(UI.button("", func():
		close_plan()
		_view.fit(), 14), "fit_all", EditorIcons.tip("Whole world", "Home  ·  middle click", "Turns and zooms the globe to show the whole world."))
	fit.focus_mode = FOCUS_NONE
	top.add_child(fit)
	var me := EditorIcons.dress(UI.button("", func():
		close_plan()
		_view.centre_on_you(), 14), "ship", EditorIcons.tip("Find yourself", "", "Turns the globe to where you are (or your ship)."))
	me.focus_mode = FOCUS_NONE
	top.add_child(me)
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(row)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(880, 590)
	stack.size_flags_horizontal = SIZE_EXPAND_FILL
	stack.size_flags_vertical = SIZE_EXPAND_FILL
	row.add_child(stack)
	_view = GlobeView.new()
	_view.page = self
	_view.set_anchors_preset(PRESET_FULL_RECT)
	_view.selected.connect(func(_k): _update_info())
	stack.add_child(_view)
	_plan = TownPlan.new()
	_plan.page = self
	_plan.set_anchors_preset(PRESET_FULL_RECT)
	_plan.visible = false
	_plan.mouse_filter = Control.MOUSE_FILTER_IGNORE   # (blending in: the globe's the one driven)
	stack.add_child(_plan)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(370, 0)
	col.add_theme_constant_override("separation", 8)
	row.add_child(col)
	col.add_child(UI.section("SELECTED"))
	_info = _rich(250)
	col.add_child(_info)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	_plan_btn = EditorIcons.dress(UI.button("Town plan", func(): open_plan(_view.selected_key), 15), "buildings", EditorIcons.tip("Town plan", "click  ·  zoom in",
		"The town from above: its buildings, its square and landing field, and its people's places named - the palace, the shrine, the storehouse, the ore buyer, the courier's office, the local pilot."))
	_plan_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_look = EditorIcons.dress(UI.button("", func(): _view.look_at_selected(), 15), "eye", EditorIcons.tip("Look at it", "double click", "Turns the globe to it."))
	for b in [_plan_btn, _look]:
		b.focus_mode = FOCUS_NONE
		btns.add_child(b)
	col.add_child(btns)
	col.add_child(UI.section("KNOWN ON THIS WORLD"))
	_list = _rich(200)
	_list.size_flags_vertical = SIZE_EXPAND_FILL
	_list.meta_clicked.connect(func(m):
		close_plan()
		_view.select(str(m))
		_view.look_at_selected())
	col.add_child(_list)


func _legend(c: Color, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var dot := ColorRect.new()
	dot.color = c
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(dot)
	h.add_child(UI.label(text, 14, UI.TEXT_DIM))
	return h


func _rich(h: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = true
	r.custom_minimum_size = Vector2(0, h)
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_font_size_override("bold_font_size", 14)
	return r


func cosmos() -> Node:
	var c := world if world else (get_tree().current_scene if is_inside_tree() else null)
	return c if c and c.has_method("planet_below") else null


## The planet you're on (on foot, landed, or low over it), or null.
func planet() -> CosmosPlanet:
	var c := cosmos()
	if c == null:
		return null
	if c.walker and c.walker.planet:
		return c.walker.planet
	return c.planet_below(c.ship.global_position, 3000.0) if c.ship else null


## The planet the map shows: {id, rec, shape, radius, towns, node} - picked on
## the solar map, else the one you're on, else the nearest; {} if none.
func target() -> Dictionary:
	if not source.is_empty():
		var sh: PlanetShape = source["shape"]
		return {"id": str(source["rec"].get("id", "")), "rec": source["rec"], "shape": sh, "radius": sh.radius, "towns": source.get("towns", []), "node": null}
	var c := cosmos()
	if c == null:
		return {}
	var pl: Node = picked if picked != null and is_instance_valid(picked) else planet()
	if pl == null and c.ship:
		var best := INF
		for p: CosmosPlanet in c.planets:
			var d: float = c.ship.global_position.distance_to(p.global_position) - p.radius
			if d < best:
				best = d
				pl = p
	if pl == null:
		return {}
	var cp := pl as CosmosPlanet
	return {"id": str(cp.rec.get("id", cp.name)), "rec": cp.rec, "shape": cp.shape, "radius": cp.radius, "towns": cp.towns, "node": cp}


## Shows `pl` (a CosmosPlanet; null: where you are).
func show_planet(pl: Node) -> void:
	picked = pl
	refresh()


## Opened (MapsPage.show_sub): the world you're on (or nearest), turned at
## once to where you are - as Find yourself does, but no easing; `keep_pick`:
## the world picked on the solar map kept.
func focus_you(keep_pick := false) -> void:
	if not keep_pick:
		picked = null
	refresh()
	close_plan(true)
	var o: Dictionary = _view.all.get("you", _view.all.get("ship", {}))
	if not o.is_empty():
		_view.turn_to(o["dir"], R * 1.6)
	else:   # (out in space: the side of it that faces you)
		var c := cosmos()
		var node: Node3D = _t.get("node")
		if c == null or not is_instance_valid(node) or c.ship == null:
			return
		var d: Vector3 = node.to_local(c.ship.global_position)   # (the globe's in the world's own frame: it turns)
		if d.length() < 1.0:
			return
		_view.turn_to(d, R * 2.7)
	_view.snap()


func refresh() -> void:
	var t := target()
	if t.is_empty():
		_title.text = "PLANET MAP  -  no world in this system"
		_t = {}
		_view.set_planet({})
		_update_info()
		return
	if str(t["id"]) != str(_t.get("id", "")):
		_t = t
		close_plan()
		_view.set_planet(t)
	_t = t
	var type := str(t["rec"].get("type", ""))
	var share := 1.0 if (t["shape"] as PlanetShape).kind == "gas" else Galaxy.planet_fog(str(t["id"])).explored_share()
	_title.text = "PLANET MAP  -  %s  (%s, %d%% explored)" % [str(t["rec"].get("name", "?")).to_upper(), Planets.TYPES.get(type, {}).get("label", type), roundi(share * 100.0)]
	_ensure(t)
	_view.rebuild()
	_update_info()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	# The globe's mesh (a worker's), when it's done.
	var id := str(_t.get("id", ""))
	if id != "" and not _meshes.has(id) and _tasks.has(id) and WorkerThreadPool.is_task_completed(_tasks[id][0]):
		WorkerThreadPool.wait_for_task_completion(_tasks[id][0])
		_meshes[id] = _tasks[id][1]["mesh"]
		_tasks.erase(id)
		while _meshes.size() > KEEP:   # (the oldest let go: a few MB each)
			_meshes.erase(_meshes.keys()[0])
		_view.set_mesh(_meshes[id])
	for k in _road_tasks.keys():
		if WorkerThreadPool.is_task_completed(_road_tasks[k][0]):
			WorkerThreadPool.wait_for_task_completion(_road_tasks[k][0])
			var res: Dictionary = _road_tasks[k][1]
			_road_tasks.erase(k)
			CosmosRoads.store(k, res.get("r", []), float(res.get("radius", 1.0)))
			_roads_ready(k)
	for k in _plan_tasks.keys():
		if WorkerThreadPool.is_task_completed(_plan_tasks[k][0]):
			WorkerThreadPool.wait_for_task_completion(_plan_tasks[k][0])
			var img: Image = _plan_tasks[k][1]["img"]
			_plans[k] = ImageTexture.create_from_image(img)
			_plan_tasks.erase(k)
			while _plans.size() > KEEP:
				_plans.erase(_plans.keys()[0])
			_plan.queue_redraw()
	# (twice a second: where you are, a planet you've landed on since)
	_follow_t += delta
	if _follow_t > 0.5:
		_follow_t = 0.0
		var t := target()
		if not t.is_empty() and str(t["id"]) != id:
			refresh()
		else:
			_view.follow()
			_update_info()


## The globe of `t`: made on a worker the first time (and its roads).
func _ensure(t: Dictionary) -> void:
	_want_roads(t)
	var id := str(t["id"])
	if _meshes.has(id):
		_view.set_mesh(_meshes[id])
		return
	if _tasks.has(id):
		return
	var out := {}
	var shape: PlanetShape = t["shape"]
	_tasks[id] = [WorkerThreadPool.add_task(func(): out["mesh"] = build_globe(shape), false, "planet globe"), out]


## The ground's height shown (m above the radius - the sea's top where it's under).
static func shown_height(shape: PlanetShape, d: Vector3) -> float:
	if shape.kind == "gas":
		return 0.0
	var h := shape.height(d)
	return maxf(h, 0.0) if shape.sea > 0 else h


## Where a planet-local direction is on the globe (map units).
static func on_globe(shape: PlanetShape, d: Vector3, lift := 0.0) -> Vector3:
	return d * (R * (1.0 + shown_height(shape, d) / shape.radius * EXAG) + lift)


## The ground's colour at `d` (height `h`): the planet's own palette.
static func ground_colour(shape: PlanetShape, d: Vector3, h: float) -> Color:
	var L := shape.look
	if shape.kind == "gas":
		var a: Color = L.get("gas_a", L.get("color_dark", Color(0.55, 0.45, 0.35)))
		var b: Color = L.get("gas_b", L.get("color_light", Color(0.85, 0.75, 0.55)))
		var c: Color = L.get("gas_c", Color(0.9, 0.85, 0.75))
		var k := sin(d.y * 13.0 + sin(d.x * 3.0 + d.z * 2.0) * 0.6) * 0.5 + 0.5
		return a.lerp(b, k).lerp(c, (sin(d.y * 31.0) * 0.5 + 0.5) * 0.3)
	var lo: Color = L.get("land_low", Color(0.3, 0.45, 0.2))
	var mid: Color = L.get("land_mid", Color(0.45, 0.42, 0.3))
	var hi: Color = L.get("land_high", Color(0.5, 0.48, 0.45))
	var peak: Color = L.get("land_peak", Color(0.9, 0.9, 0.92))
	if shape.sea == 1 and h < 0.0:
		return (L.get("water_shallow", Color(0.15, 0.45, 0.6)) as Color).lerp(L.get("water_deep", Color(0.03, 0.12, 0.3)), clampf(-h / (shape.amp * 0.4), 0.0, 1.0))
	if shape.sea == 3 and h < 0.0:
		return Color(1.0, 0.35, 0.05).lerp(Color(0.5, 0.08, 0.02), clampf(-h / (shape.amp * 0.3), 0.0, 1.0))
	var k := clampf(h / (shape.amp * 1.6), 0.0, 1.0)
	var col := lo.lerp(mid, smoothstep(0.0, 0.35, k)).lerp(hi, smoothstep(0.3, 0.7, k)).lerp(peak, smoothstep(0.7, 1.0, k))
	if shape.sea == 2 and h < shape.amp * 0.05:
		col = col.lerp(Color(0.85, 0.92, 1.0), 0.7)
	return col


## The globe's mesh (a worker's): a cube-sphere, N x N quads a face, each
## vertex on the ground (raised EXAG times), its colour the ground's (linear),
## its normal from its neighbours (a ring past the face's edges: no seams).
static func build_globe(shape: PlanetShape) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var uvs := PackedVector2Array()
	var wet := shape.sea == 1 or shape.sea == 3
	var wt := shape.water           # (its lakes, its rivers)
	var S := N + 3                 # (samples a side: the face's N + 1, and one more each way)
	for f in 6:
		var ax := PlanetShape.face_axes(f)
		var pts := PackedVector3Array()
		pts.resize(S * S)
		var hs := PackedFloat32Array()
		hs.resize(S * S)
		for j in S:
			for i in S:
				var d := PlanetShape.face_dir(ax[0], ax[1], ax[2], -1.0 + 2.0 * (i - 1) / N, -1.0 + 2.0 * (j - 1) / N)
				var h := 0.0 if shape.kind == "gas" else shape.height(d)
				var li := wt.lake_at(d) if wt else -1
				pts[j * S + i] = d * R * (1.0 + (maxf(h, 0.0) if shape.sea > 0 else h) / shape.radius * EXAG)
				if li >= 0:   # (a lake: flat at its water's level, coloured as water)
					pts[j * S + i] = d * R * (1.0 + float(wt.lakes[li]["level"]) / shape.radius * EXAG)
					h = -0.03 * shape.amp
				hs[j * S + i] = h
		var base := verts.size()
		for j in range(1, N + 2):
			for i in range(1, N + 2):
				var p := pts[j * S + i]
				var n := (pts[j * S + i + 1] - pts[j * S + i - 1]).cross(pts[(j + 1) * S + i] - pts[(j - 1) * S + i]).normalized()
				if n.dot(p) < 0.0:
					n = -n
				verts.append(p)
				norms.append(n)
				var h := hs[j * S + i]
				cols.append(ground_colour(shape, p.normalized(), maxf(h, 0.0) if wet else h).srgb_to_linear())
				uvs.append(Vector2(h / shape.amp, 0.0))   # (the seas coloured in the shader by it: smooth shores)
		var W := N + 1
		var flip := false
		var p0 := verts[base]
		if (verts[base + 1] - p0).cross(verts[base + W] - p0).dot(p0) > 0.0:
			flip = true   # (Godot's front faces wind clockwise)
		for j in N:
			for i in N:
				var a := base + j * W + i
				if flip:
					idx.append_array([a, a + W, a + 1, a + 1, a + W, a + W + 1])
				else:
					idx.append_array([a, a + 1, a + W, a + 1, a + W + 1, a + W])
	if wt:
		_globe_rivers(shape, wt, verts, norms, cols, uvs, idx)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Its rivers on the globe: ribbons over the ground (wide enough to be seen), coloured as water.
static func _globe_rivers(shape: PlanetShape, wt: PlanetWater, verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array, idx: PackedInt32Array) -> void:
	var water: Color = (shape.look.get("water_shallow", Color(0.15, 0.45, 0.6)) as Color).srgb_to_linear()
	for rv in wt.rivers:
		var first := int(rv["first"])
		var n := int(rv["count"])
		var base := verts.size()
		var k := 0
		for q in range(first, first + n, 2):
			var p := wt.pts[q]
			var u := p.normalized()
			var b := mini(q + 2, first + n - 1)
			var a := maxi(q - 2, first)
			var side := (wt.pts[b] - wt.pts[a]).cross(u).normalized()
			var hw := maxf(wt.hw[q] / shape.radius * R, 0.16)
			var lift := R * (1.0 + maxf(wt.lvl[q], 0.0) / shape.radius * EXAG) + 0.08
			for sgn in [-1.0, 1.0]:
				var d: Vector3 = (u * R + side * hw * sgn).normalized()
				verts.append(d * lift)
				norms.append(d)
				cols.append(water)
				uvs.append(Vector2(-0.05, 0.0))
			k += 1
		for t in k - 1:
			var a0 := base + t * 2
			var tri := [a0, a0 + 1, a0 + 2, a0 + 1, a0 + 3, a0 + 2]
			var c0 := verts[a0]
			if (verts[a0 + 1] - c0).cross(verts[a0 + 2] - c0).dot(c0) > 0.0:
				tri = [a0, a0 + 2, a0 + 1, a0 + 1, a0 + 2, a0 + 3]
			idx.append_array(tri)


## The globe's material for `shape` (its fog; its seas' colours).
static func globe_material(shape: PlanetShape, fog: PlanetFog) -> ShaderMaterial:
	var m := MapKit.globe_material(fog.texture() if fog else null)
	var L := shape.look
	if shape.sea == 1:
		m.set_shader_parameter("sea_kind", 1.0)
		m.set_shader_parameter("sea_a", L.get("water_shallow", Color(0.15, 0.45, 0.6)))
		m.set_shader_parameter("sea_b", L.get("water_deep", Color(0.03, 0.12, 0.3)))
		m.set_shader_parameter("sea_depth", 0.4)
	elif shape.sea == 3:
		m.set_shader_parameter("sea_kind", 3.0)
		m.set_shader_parameter("sea_a", Color(1.0, 0.35, 0.05))
		m.set_shader_parameter("sea_b", Color(0.5, 0.08, 0.02))
		m.set_shader_parameter("sea_depth", 0.3)
	return m


# --- The marks --------------------------------------------------------------------------

## What's marked on the globe: key -> {kind, name, dir, pos, r, ...} - what
## you've seen of it (the fog), you and your ship always.
func gather() -> Dictionary:
	var out := {}
	if _t.is_empty():
		return out
	var sh: PlanetShape = _t["shape"]
	var pid := str(_t["id"])
	var gas := sh.kind == "gas"
	var fog := Galaxy.planet_fog(pid)
	var towns: Array = _t["towns"]
	for i in towns.size():
		var s: Dictionary = towns[i]
		var d: Vector3 = s["dir"]
		var visited := Galaxy.town_visited(pid, str(s["name"]))
		if not visited and not fog.explored(d):
			continue
		var city := str(s["kind"]) == "city"
		out["town:%d" % i] = {"kind": "town", "name": ("Palace of %s" if city else "%s") % str(s["name"]), "town": str(s["name"]), "dir": d,
			"pos": on_globe(sh, d, 0.15), "ground": on_globe(sh, d), "r": 14.0, "site": s, "city": city, "visited": visited, "color": TOWN_COL}
	var c := cosmos()
	var node: Node = _t["node"]
	if c and node and not gas:
		if c.has_method("dungeons_of"):
			var ds: Array = c.dungeons_of(node)
			for i in ds.size():
				var site: Dictionary = ds[i][0]
				var d: Vector3 = site["dir"]
				if fog.explored(d):
					out["cave:%d" % i] = {"kind": str(site["kind"]), "name": str(site["name"]), "dir": d, "pos": on_globe(sh, d, 0.15), "r": 10.0, "color": CAVE_COL}
		if c.has_method("camps_of"):
			var cs: Array = c.camps_of(node)
			for i in cs.size():
				var d: Vector3 = (cs[i][0] as Vector3).normalized()
				if fog.explored(d):
					out["camp:%d" % i] = {"kind": "camp", "name": "Pirate camp", "dir": d, "pos": on_globe(sh, d, 0.15), "r": 10.0, "color": CAMP_COL}
	if c and node:
		var pl := node as Node3D
		if c.ship and is_instance_valid(c.ship):
			var lp: Vector3 = pl.to_local(c.ship.global_position)   # (planet-local: the globe's frame)
			var alt := lp.length() - (_t["radius"] as float)
			if alt < (_t["radius"] as float) * 3.0:
				var d := lp.normalized()
				out["ship"] = {"kind": "ship", "name": "Your ship", "dir": d, "pos": d * maxf(on_globe(sh, d, 0.3).length(), R * (1.0 + alt / (_t["radius"] as float) * EXAG * 0.3)), "r": 12.0, "color": NeonTheme.INFO, "alt": alt}
		if c.walker and c.walker.planet == node:
			var wl: Vector3 = pl.to_local(c.walker.global_position)
			var u := wl.normalized()
			var east := Vector3.UP.cross(u).normalized()
			if east.length() < 0.5:
				east = Vector3.RIGHT
			var north := u.cross(east)
			var f: Vector3 = pl.global_basis.inverse() * (c.walker.facing as Vector3)   # (your way, in its frame)
			out["you"] = {"kind": "you", "name": "You", "dir": u, "pos": on_globe(sh, u, 0.3), "ground": on_globe(sh, u), "r": 12.0, "color": Color.WHITE,
				"heading": atan2(f.dot(east), f.dot(north)), "north": north, "east": east}
	return out


## The selection's details, and the list of what's known here.
func _update_info() -> void:
	var o: Dictionary = _view.all.get(_view.selected_key, {})
	if o.is_empty():
		var txt := _describe_planet()
		if txt != _info.text:
			_info.text = txt
		_plan_btn.disabled = true
		_look.disabled = true
	else:
		var txt := describe(o)
		if txt != _info.text:
			_info.text = txt
		_plan_btn.disabled = not (o["kind"] == "town" and o["visited"])
		_look.disabled = false
	var keys: Array = _view.all.keys().filter(func(k): return not k in ["you", "ship"])
	var sig := str(keys)
	if sig != _list_sig:
		_list_sig = sig
		var lines := []
		for k in keys:
			var q: Dictionary = _view.all[k]
			lines.append("[url=%s][color=#%s]%s[/color][/url]  [color=#%s]%s[/color]" % [k, (q["color"] as Color).to_html(false), q["name"],
				UI.TEXT_DIM.to_html(false), _kind_name(q)])
		_list.text = "\n".join(lines) if not lines.is_empty() else "[color=#%s]Nothing seen yet - walk or fly low over the ground to chart it.[/color]" % UI.TEXT_DIM.to_html(false)


func _kind_name(o: Dictionary) -> String:
	match str(o["kind"]):
		"town":
			return ("City" if o["city"] else "Village") + ("" if o["visited"] else " (not visited)")
		"cave":
			return "Cave"
		"dungeon":
			return "Dungeon"
		"camp":
			return "Pirate camp"
	return ""


func _describe_planet() -> String:
	if _t.is_empty():
		return "[color=#%s]No world here to chart.[/color]" % UI.TEXT_DIM.to_html(false)
	var rec: Dictionary = _t["rec"]
	var sh: PlanetShape = _t["shape"]
	var type := str(rec.get("type", ""))
	var lines := ["[b][color=#%s]%s[/color][/b]" % [NeonTheme.HEAD.to_html(false), str(rec.get("name", "?")).to_upper()]]
	lines.append("%s  ·  radius %.1f km" % [Planets.TYPES.get(type, {}).get("label", type), sh.radius / 1000.0])
	if sh.kind == "gas":
		lines.append("A gas giant: no ground to walk.")
	else:
		var fog := Galaxy.planet_fog(str(_t["id"]))
		lines.append("Explored: %d%%" % roundi(fog.explored_share() * 100.0))
		var towns: Array = _t["towns"]
		var seen := _view.all.keys().filter(func(k): return str(k).begins_with("town:")).size()
		lines.append("Towns known: %d of %d" % [seen, towns.size()] if not towns.is_empty() else "No towns.")
		var me: Dictionary = _view.all.get("you", _view.all.get("ship", {}))
		if not me.is_empty():   # (where you are on it: latitude and longitude - the globe's grid every 30 degrees)
			var d: Vector3 = me["dir"]
			var lat := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
			var lon := rad_to_deg(atan2(d.x, d.z))
			lines.append("You: %.2f° %s, %.2f° %s" % [absf(lat), "N" if lat >= 0.0 else "S", absf(lon), "E" if lon >= 0.0 else "W"])
	lines.append("")
	lines.append("[color=#%s]Pick a mark for its details. A town you've walked into shows its plan.[/color]" % UI.TEXT_DIM.to_html(false))
	return "\n".join(lines)


func describe(o: Dictionary) -> String:
	var lines := ["[b][color=#%s]%s[/color][/b]" % [(o["color"] as Color).to_html(false), str(o["name"]).to_upper()]]
	var d: Vector3 = o["dir"]
	var lat := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
	var lon := rad_to_deg(atan2(d.x, d.z))
	match str(o["kind"]):
		"town":
			var s: Dictionary = o["site"]
			lines.append("%s of %s" % ["City" if o["city"] else "Village", Galaxy.empire_name(str(s.get("empire", "")))])
			if o["visited"]:
				lines.append("Visited - its plan: click it, or zoom in over it.")
				var names: Array = CosmosTown.places(str(s["kind"])).map(func(p): return p[1])
				lines.append("[color=#%s]%s[/color]" % [UI.TEXT_DIM.to_html(false), ", ".join(names)])
			else:
				lines.append("Seen from afar - walk into it for its plan.")
		"cave":
			lines.append("A cave: its mouth a rock arch.")
		"dungeon":
			lines.append("A dungeon: a stone gateway down.")
		"camp":
			lines.append("Sea Peoples' raiders camp here.")
		"ship":
			lines.append("Altitude %d m" % roundi(maxf(float(o.get("alt", 0.0)), 0.0)))
		"you":
			lines.append("On foot.")
	lines.append("%.1f° %s, %.1f° %s" % [absf(lat), "N" if lat >= 0.0 else "S", absf(lon), "E" if lon >= 0.0 else "W"])
	var c := cosmos()
	var me: Dictionary = _view.all.get("you", _view.all.get("ship", {}))
	if not me.is_empty() and o != me and not _t.is_empty():
		var m := (me["dir"] as Vector3).angle_to(d) * float(_t["radius"])
		lines.append("%s from you" % (("%d m" % roundi(m)) if m < 1000.0 else ("%.1f km" % (m / 1000.0))))
	return "\n".join(lines)


# --- Town plans -------------------------------------------------------------------------

## Shows the town marked `key`'s plan (if you've been in it): the globe dives
## onto it (eased, ANIM_S) and the plan blends in over it; `now`: at once.
func open_plan(key: String, now := false) -> void:
	var o: Dictionary = _view.all.get(key, {})
	if o.is_empty() or o["kind"] != "town" or not o["visited"]:
		return
	_view.select(key)
	prepare_plan(key)
	if plan_shown():
		_plan.fit()
	else:
		_view.fly_into(key, 0.0 if now else ANIM_S)
		if now:
			_to_plan()
			_plan.fit()
	_update_info()


## The plan of the town marked `key` made ready (drawn on a worker the first
## time) and laid where the town is.
func prepare_plan(key: String) -> void:
	var o: Dictionary = _view.all.get(key, {})
	if o.is_empty() or o["kind"] != "town" or not o["visited"]:
		return
	var s: Dictionary = o["site"]
	var k := plan_key(str(_t["id"]), s)
	if not _plans.has(k) and not _plan_tasks.has(k):
		var out := {}
		var kind := str(s["kind"])
		var seed := int(s["seed"])
		var emp := str(s["empire"])
		var ways := town_ways((_t["towns"] as Array).find(s))
		_plan_tasks[k] = [WorkerThreadPool.add_task(func(): out["img"] = bake_plan(kind, seed, emp, ways), false, "town plan"), out]
	if _plan.key != k:
		_plan.show_town(o, k, _t)


## The roads of `t` on its globe: from the roads made already (CosmosRoads), or
## its network made on a worker now (as CosmosRoads would) - drawn when it's done.
func _want_roads(t: Dictionary) -> void:
	var sh: PlanetShape = t["shape"]
	var towns: Array = t.get("towns", [])
	if sh.kind != "rocky" or towns.size() < 2:
		_view.set_roads([])
		return
	var key := CosmosRoads.key_of(t["rec"])
	if CosmosRoads.has_roads(key):
		_roads_ready(key)
	elif not _road_tasks.has(key):
		var out := {"radius": sh.radius}
		var tw: Array = towns.duplicate(true)
		_road_tasks[key] = [WorkerThreadPool.add_task(func(): out["r"] = CosmosRoads.network(sh, tw), false, "map roads"), out]


## A world's roads made: their lines (once), on the globe if it's the one shown; its towns' plans redrawn with them.
func _roads_ready(key: String) -> void:
	if not _roads.has(key):
		_roads[key] = road_lines(CosmosRoads.cached(key), float(_t.get("radius", 1000.0)) if not _t.is_empty() else 1000.0)
		for pk in _plans.keys():   # (plans drawn before: their roads in now)
			if str(pk).begins_with(str(_t.get("id", "?")) + ":"):
				_plans.erase(pk)
		if _plan and _view.town != "":
			prepare_plan(_view.town)
	if not _t.is_empty() and CosmosRoads.key_of(_t["rec"]) == key:
		_view.set_roads(_roads[key])


## A world's roads as lines to draw: [[unit dirs, main]] - from gate to gate (in
## the towns, their streets), simplified (Douglas-Peucker, to ~8 m on the ground).
static func road_lines(roads: Array, radius: float) -> Array:
	var out: Array = []
	for r in roads:
		var pts: PackedVector3Array = r["pts"]
		var dr: Vector2i = r.get("drawn", Vector2i(0, pts.size() - 1))
		out.append([simplify(pts.slice(dr.x, dr.y + 1), 8.0 / radius), bool(r.get("main", false))])
	for r in roads:   # (its bridges: a pale stone casing under the road where it crosses the water - [dirs, main, pieces, true])
		var pts: PackedVector3Array = r["pts"]
		for br in r.get("bridges", []):
			out.append([simplify(pts.slice(int(br["i0"]), int(br["i1"]) + 1), 8.0 / radius), bool(r.get("main", false)), null, true])
	return out


## A road's line cut into ~25 m pieces: [their unit dirs, their places on the globe (no lift)].
static func road_pieces(shape: PlanetShape, dirs: PackedVector3Array) -> Array:
	var piece := 25.0 / maxf(shape.radius, 1.0)
	var pd := PackedVector3Array()
	var pg := PackedVector3Array()
	for i in dirs.size():
		if i > 0:
			var n := maxi(1, ceili(dirs[i - 1].angle_to(dirs[i]) / piece))
			for j in range(1, n):
				var d: Vector3 = dirs[i - 1].slerp(dirs[i], float(j) / n)
				pd.append(d)
				pg.append(on_globe(shape, d))
		pd.append(dirs[i])
		pg.append(on_globe(shape, dirs[i]))
	return [pd, pg]


## Douglas-Peucker: the points that keep the line within `eps` (unit-direction units).
static func simplify(pts: PackedVector3Array, eps: float) -> PackedVector3Array:
	if pts.size() < 3:
		return pts
	var keep := PackedByteArray()
	keep.resize(pts.size())
	keep[0] = 1
	keep[pts.size() - 1] = 1
	var stack: Array = [[0, pts.size() - 1]]
	while not stack.is_empty():
		var se: Array = stack.pop_back()
		var a: int = se[0]
		var b: int = se[1]
		var worst := -1.0
		var wi := -1
		for i in range(a + 1, b):
			var d := Geometry3D.get_closest_point_to_segment(pts[i], pts[a], pts[b]).distance_to(pts[i])
			if d > worst:
				worst = d
				wi = i
		if wi >= 0 and worst > eps:
			keep[wi] = 1
			stack.append([a, wi])
			stack.append([wi, b])
	var out := PackedVector3Array()
	for i in pts.size():
		if keep[i]:
			out.append(pts[i])
	return out


## The roads that leave town `i` of the world shown, as they come to its gates - town-local
## [x, z] points from its gate outward (~150 m), and main: [[PackedVector2Array, main]].
func town_ways(i: int) -> Array:
	var out: Array = []
	if _t.is_empty() or i < 0 or i >= (_t["towns"] as Array).size():
		return out
	var roads := CosmosRoads.cached(CosmosRoads.key_of(_t["rec"]))
	var s: Dictionary = _t["towns"][i]
	var R: float = _t["radius"]
	var inv := CosmosTown.frame(s, R).affine_inverse()
	for r in roads:
		var pts: PackedVector3Array = r["pts"]
		var dr: Vector2i = r.get("drawn", Vector2i(0, pts.size() - 1))
		var line := PackedVector2Array()
		if int(r["a"]) == i:
			for k in range(dr.x, mini(dr.x + 60, dr.y + 1)):
				var q: Vector3 = inv * (pts[k] * (R + float(s["h"])))
				line.append(Vector2(q.x, q.z))
		elif int(r["b"]) == i:
			for k in range(dr.y, maxi(dr.y - 60, dr.x - 1), -1):
				var q: Vector3 = inv * (pts[k] * (R + float(s["h"])))
				line.append(Vector2(q.x, q.z))
		if line.size() >= 2:
			out.append([line, bool(r.get("main", false))])
	return out


## How much of the plan shows at `ppm` (the globe's px a metre at the town):
## none at a PLAN_FROM-th of the plan's fit zoom, all of it at its fit.
func blend_at(ppm: float) -> float:
	var fit := _plan.fit_ppm()
	return smoothstep(0.0, 1.0, clampf(log(ppm * PLAN_FROM / fit) / log(PLAN_FROM), 0.0, 1.0))


## The globe moved (GlobeView._view_changed): the plan laid over it as it is.
func globe_moved() -> void:
	if plan_shown():
		return
	var a := _view.blend
	if a <= 0.002 or _plan.key == "":
		_plan.visible = false
		return
	_plan.visible = true
	_plan.follow_globe(_view, a)


## Zoomed all the way in: the plan alone (its own zoom from here on).
func _to_plan() -> void:
	_plan.enter(_view.ppm(), _view.take_carry())
	_plan.visible = true
	_view.visible = false
	_globe_btn.visible = true


## Zoomed out of the plan past its fit (`ppm` now, eased toward `ppm_to`):
## the globe again, where the plan was, the plan fading back into it.
func plan_out(ppm: float, ppm_to: float) -> void:
	_plan.full = false
	_plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.visible = true
	_globe_btn.visible = false
	_view.take_over(_plan.centre_dir(), ppm, ppm_to)
	globe_moved()


## Back to the globe: zoomed out of the town (eased; `now`: at once).
func close_plan(now := false) -> void:
	if _plan == null:
		return
	if plan_shown():
		plan_out(_plan._ppm, _plan._ppm)
	if now:
		_view.leave_town(0.0)
		_plan.visible = false
	elif _view.blend > 0.0:
		_view.leave_town(ANIM_S)


## The plan alone (the globe all zoomed in)?
func plan_shown() -> bool:
	return _plan != null and _plan.visible and _plan.full


## How far into the plan the view is (0: the globe, 1: the plan alone).
func plan_blend() -> float:
	return 1.0 if plan_shown() else (_view.blend if _view else 0.0)


## Where the middle of a town's plan is (a unit direction, planet-local).
static func plan_centre_dir(s: Dictionary, radius: float) -> Vector3:
	var c := plan_rect(str(s["kind"])).get_center()
	return (CosmosTown.frame(s, radius) * Vector3(c.x, 0.0, c.y)).normalized()


static func plan_key(pid: String, s: Dictionary) -> String:
	return "%s:%s" % [pid, str(s["name"])]


## A town's plan picture (a worker's): its buildings from above (CosmosTown's
## own layout for its seed), the paved square, the landing field - town-local
## metres from plan_rect(kind)'s corner, PLAN_PPM pixels a metre. The roofs
## lighter the taller (their tops), each edged dark.
static func bake_plan(kind: String, seed: int, empire: String, ways: Array = []) -> Image:
	var rect := plan_rect(kind)
	var w := int(rect.size.x * PLAN_PPM)
	var h := int(rect.size.y * PLAN_PPM)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var lay := CosmosTown.layout(kind)
	var half: float = lay["half"]
	var port: Vector3 = lay["port"]
	var px := func(x0: float, z0: float, x1: float, z1: float) -> Rect2i:
		return Rect2i(int((x0 - rect.position.x) * PLAN_PPM), int((z0 - rect.position.y) * PLAN_PPM),
			maxi(1, int((x1 - x0) * PLAN_PPM)), maxi(1, int((z1 - z0) * PLAN_PPM)))
	img.fill_rect(px.call(-half, -half, half, half), Color(0.2, 0.19, 0.17))
	for wy in ways:   # (the roads out, from its gates: a dark casing, the road over it)
		for pass_k in 2:
			var wd: float = (CosmosRoads.MAIN_WIDTH if wy[1] else CosmosRoads.WIDTH) + (1.2 if pass_k == 0 else 0.0)
			var col: Color = ROAD_CASE if pass_k == 0 else (ROAD_FILL if wy[1] else TRACK_FILL).darkened(0.35)
			var line: PackedVector2Array = wy[0]
			for k in line.size() - 1:
				var a := line[k]
				var b := line[k + 1]
				var n := maxi(1, ceili(a.distance_to(b) * PLAN_PPM))
				for m in n + 1:
					var q := a.lerp(b, float(m) / n)
					img.fill_rect(px.call(q.x - wd * 0.5, q.y - wd * 0.5, q.x + wd * 0.5, q.y + wd * 0.5).intersection(Rect2i(0, 0, w, h)), col)
	for st in TownStreets.pieces(kind, empire):   # (its streets between the blocks, paved - the roads out start at their ends)
		var sr: Rect2 = st["r"]
		img.fill_rect(px.call(sr.position.x, sr.position.y, sr.end.x, sr.end.y), Color(0.36, 0.33, 0.28) if st["main"] else Color(0.3, 0.28, 0.24))
	img.fill_rect(px.call(port.x - 34, port.z - 34, port.x + 34, port.z + 34), Color(0.13, 0.13, 0.14))
	img.fill_rect(px.call(port.x - 30, port.z - 0.4, port.x + 30, port.z + 0.4), Color(0.45, 0.4, 0.3))
	img.fill_rect(px.call(port.x - 0.4, port.z - 30, port.x + 0.4, port.z + 30), Color(0.45, 0.4, 0.3))
	var solids: Array = CosmosTown.plan_of(kind, seed, empire)
	solids.sort_custom(func(a: AABB, b: AABB): return a.end.y < b.end.y)
	var edge := Color(0.05, 0.04, 0.03)
	for b: AABB in solids:
		if b.end.y < 0.3:
			continue
		var r: Rect2i = px.call(b.position.x, b.position.z, b.end.x, b.end.z)
		var k := clampf(b.end.y / 13.0, 0.0, 1.0)
		var col := Color(0.42, 0.36, 0.28).lerp(Color(0.93, 0.84, 0.68), k)
		if b.size.y < 1.4 and b.end.y < 1.6:
			col = Color(0.33, 0.3, 0.26)   # (low walls, jars, altars)
		img.fill_rect(r.grow(1), edge)
		img.fill_rect(r, col)
	img.generate_mipmaps()   # (smooth while it's small on the screen, blending in)
	return img


## The plan's extent (town-local x, z metres): the square and the field.
static func plan_rect(kind: String) -> Rect2:
	var lay := CosmosTown.layout(kind)
	var half: float = lay["half"]
	var port: Vector3 = lay["port"]
	return Rect2(-half - 8.0, -half - 8.0, port.x + 34.0 + 8.0 + half + 8.0, half * 2.0 + 16.0).merge(Rect2(port.x - 42.0, -42.0, 84.0, 84.0))


static func plan_texture(k: String) -> Texture2D:
	return _plans.get(k)


# --- The globe --------------------------------------------------------------------------

## The planet map's view: the globe in 3D, R map units across its radius.
## Its zoom is `span` - half the view's height on the ground (globe units):
## the camera comes down to ALT_MIN over the ground under it, then narrows its
## view (its fov) - so over a town you've been in it goes on closing in until
## the town's plan (TownPlan, laid over it where the town is, the same north
## and scale) has blended in whole: then the plan alone, its own zoom going on
## from there (and back out the same way).
class GlobeView extends Map3DView:
	const ALT_MIN := R * 0.03    # (the camera's lowest over the ground: nearer, it narrows its view)
	const FOV := 50.0
	var page: Node
	## Everything marked (seen or not on this side): key -> as gather() makes them.
	var all := {}
	## The zoom: half the view's height on the ground (globe units), eased to _span_t.
	var span := 1.0
	## The town you've been in that the view is over ("": none) - its plan
	## blending in as you come close, `blend` of it (0..1).
	var town := ""
	var blend := 0.0
	var _span_t := 1.0
	var _ground := R             # (the ground's radius under the middle of the view)
	var _ground_at := Vector3.ZERO
	var _set_dist := -1.0        # (the distance this view set: another one is someone's jump)
	var _carry := 1.0            # (the wheel's zoom in past the hand-over: the plan's)
	var _anim := {}              # (a dive onto a town, or out of one: eased)
	var _town_dirs := {}         # town key -> [its plan's middle (a direction), its reach (rad)]
	var _globe: MeshInstance3D
	var _mat: ShaderMaterial
	var _fog: PlanetFog
	var _fog_v := -1
	var _sh: PlanetShape
	var _roads_mi: MeshInstance3D
	var road_lines: Array = []   # [[unit dirs, main]] (PlanetMapPage.road_lines): drawn where you've seen the ground
	var road_segs := 0           # (the segments drawn: the fog's share of them)

	func _init() -> void:
		super()
		min_dist = R * 1.03
		max_dist = R * 6.0
		anim_hz = 4.0
		overlay_hz = 6.0
		snap_to(Vector3.ZERO, R * 2.7)
		_globe = MeshInstance3D.new()
		_globe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(_globe)
		_roads_mi = MapKit.Lines.new().into(null)
		world.add_child(_roads_mi)

	## The world's roads to draw (on its ground, under the fog like the rest).
	func set_roads(lines: Array) -> void:
		road_lines = lines
		_draw_roads()

	## Its roads as lines on the globe: a dark casing, the road over it - a main
	## road (city to city) wider and warmer than a village's track; only where
	## you've seen the ground (redrawn as the fog lifts).
	func _draw_roads() -> void:
		var L := MapKit.Lines.new()
		road_segs = 0
		if _sh != null and _globe.visible:
			for pass_k in 2:
				for rl in road_lines:
					var dirs: PackedVector3Array = rl[0]
					var main: bool = rl[1]
					var bridge: bool = rl.size() > 3   # (a bridge: its casing only, wider and pale, between the road's casing and the road)
					if bridge and pass_k == 1:
						continue
					var wd: float = (3.0 if main else 1.6) + (1.8 if pass_k == 0 else 0.0) + (2.4 if bridge else 0.0)
					var col: Color = PlanetMapPage.BRIDGE_CASE if bridge else (PlanetMapPage.ROAD_CASE if pass_k == 0 else (PlanetMapPage.ROAD_FILL if main else PlanetMapPage.TRACK_FILL))
					var lift := 0.07 if bridge else (0.05 if pass_k == 0 else 0.09)
					if rl.size() < 3:   # (its ~25 m pieces and their places on the globe: worked out once - the fog judged a piece at a time,
						rl.append(PlanetMapPage.road_pieces(_sh, dirs))   # a long straight stretch shown as far as you've seen it)
					elif rl[2] == null:
						rl[2] = PlanetMapPage.road_pieces(_sh, dirs)
					var pc: Array = rl[2]
					var pd: PackedVector3Array = pc[0]
					var pg: PackedVector3Array = pc[1]
					for i in pd.size() - 1:
						if pd[i] == Vector3.ZERO or pd[i + 1] == Vector3.ZERO:
							continue   # (a break between its stretches)
						if not _fog or (_fog.explored(pd[i]) and _fog.explored(pd[i + 1])):
							L.seg(pg[i] + pd[i] * lift, pg[i + 1] + pd[i + 1] * lift, col, wd)
							if pass_k == 1:
								road_segs += 1
		L.into(_roads_mi)

	func set_planet(t: Dictionary) -> void:
		all = {}
		marks = {}
		selected_key = ""
		hover_key = ""
		town = ""
		blend = 0.0
		_anim = {}
		_town_dirs = {}
		_ground = R
		_ground_at = Vector3.ZERO
		road_lines = []
		_draw_roads()
		if t.is_empty():
			_globe.visible = false
			_sh = null
			mark_dirty()
			return
		_sh = t["shape"]
		var gas := _sh.kind == "gas"
		_fog = null if gas else Galaxy.planet_fog(str(t["id"]))
		_fog_v = _fog.version if _fog else -1
		_mat = PlanetMapPage.globe_material(_sh, _fog)
		_globe.material_override = _mat
		_globe.mesh = null
		_globe.visible = false   # (until its ground is made: "Charting the world...")
		snap_to(Vector3.ZERO, R * 2.7)
		mark_dirty()

	func set_mesh(m: Mesh) -> void:
		if _globe.mesh != m:
			_globe.mesh = m
			_globe.visible = true
			_draw_roads()
			mark_dirty()

	## The marks gathered again (the fog, where you are).
	func rebuild() -> void:
		all = page.gather()
		_town_dirs = {}
		if not all.has(selected_key):
			selected_key = ""
		if not all.has(town):
			town = ""
		_visible_marks()
		mark_dirty()

	## Twice a second: you and your ship moved, the fog lifted.
	func follow() -> void:
		if _fog and _fog.version != _fog_v:
			_fog_v = _fog.version
			_mat.set_shader_parameter("fog_tex", _fog.texture())
			_draw_roads()
			rebuild()
			return
		var fresh: Dictionary = page.gather()
		for k in ["you", "ship"]:
			if fresh.has(k) != all.has(k) or (fresh.has(k) and not (fresh[k]["pos"] as Vector3).is_equal_approx(all[k]["pos"])):
				all = fresh
				_visible_marks()
				overlay_due()
				return

	## Only the marks on the side facing the camera.
	func _visible_marks() -> void:
		marks = {}
		var cp := cam.position
		for k in all:
			var p: Vector3 = all[k]["pos"]
			if (cp - p).dot(p.normalized()) > 0.0:
				marks[k] = all[k]

	func _view_changed() -> void:
		_visible_marks()
		_find_town()
		blend = page.blend_at(ppm()) if town != "" else 0.0
		page.globe_moved()

	# --- The zoom ---

	static func _tan() -> float:
		return tan(deg_to_rad(FOV) * 0.5)

	## The span at the camera's lowest (nearer: its view narrows).
	func span_floor() -> float:
		return _tan() * ALT_MIN

	## The nearest it zooms: a town's plan whole (over a town you've been in), else span_floor().
	func span_min() -> float:
		return span_at_ppm(page._plan.fit_ppm()) if town != "" else span_floor()

	func span_max() -> float:
		return _tan() * (max_dist - R)

	## The middle of the view (a unit direction from the globe's middle).
	func view_dir() -> Vector3:
		return Vector3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw))

	## Screen px a metre on the ground in the middle of the view.
	func ppm() -> float:
		return maxf(size.y, 8.0) * 0.5 / span * _ground / _sh.radius if _sh else 1.0

	func span_at_ppm(p: float) -> float:
		return maxf(size.y, 8.0) * 0.5 * _ground / (_sh.radius * p) if _sh else 1.0

	func _span_of_dist(d: float) -> float:
		return _tan() * maxf(d - _ground, ALT_MIN)

	## The camera placed for `span`: ALT_MIN or more over the ground, its view narrowed below that.
	func _apply_span() -> void:
		var fl := span_floor()
		var d := _ground + (span / _tan() if span >= fl else ALT_MIN)
		cam.fov = FOV if span >= fl else rad_to_deg(2.0 * atan(span / ALT_MIN))
		dist = d
		_dist_t = d
		_set_dist = d

	func _update_ground() -> void:
		var vd := view_dir()
		if _sh and vd.distance_squared_to(_ground_at) > 1e-12:
			_ground_at = vd
			_ground = PlanetMapPage.on_globe(_sh, vd).length()

	## The visited town the view's over, if any (kept while you're close).
	func _find_town() -> void:
		if town != "" and all.has(town) and (blend > 0.0 or span < span_floor() * 1.5 or not _anim.is_empty()):
			return
		var vd := view_dir()
		var best := ""
		var bd := INF
		for k in all:
			var o: Dictionary = all[k]
			if o["kind"] != "town" or not o["visited"]:
				continue
			var td: Array = _town_dir(k)
			var a := vd.angle_to(td[0])
			var reach := maxf(td[1], minf(span, span_floor() * 1.5) / _ground * 0.8)
			if a < reach and a < bd:
				bd = a
				best = k
		if best != town:
			town = best
			if town != "":
				page.prepare_plan(town)

	## [the middle of its plan (a direction), how far from it the view's over it (rad)].
	func _town_dir(k: String) -> Array:
		if not _town_dirs.has(k):
			var s: Dictionary = all[k]["site"]
			var r := PlanetMapPage.plan_rect(str(s["kind"]))
			_town_dirs[k] = [PlanetMapPage.plan_centre_dir(s, _sh.radius), (r.size.length() * 0.5 + 200.0) / _sh.radius]
		return _town_dirs[k]

	## Its wheel zoom past the plan's hand-over (for the plan to go on with).
	func take_carry() -> float:
		var c := _carry
		_carry = 1.0
		return c

	## Dives onto the town `key` until its plan's whole (eased over `secs`; 0: at once).
	func fly_into(key: String, secs: float) -> void:
		if not all.has(key) or _sh == null:
			return
		town = key
		page.prepare_plan(key)
		var d: Vector3 = _town_dir(key)[0]
		var g := PlanetMapPage.on_globe(_sh, d).length()
		var s1: float = maxf(size.y, 8.0) * 0.5 * g / (_sh.radius * page._plan.fit_ppm())
		var y1 := yaw + wrapf(atan2(d.x, d.z) - yaw, -PI, PI)
		var p1 := -asin(clampf(d.y, -1.0, 1.0))
		if _set_dist > 0.0:
			_dist_t = _set_dist   # (anything set to happen meanwhile, dropped)
			dist = _set_dist
		_carry = 1.0
		if secs <= 0.0:
			yaw = y1
			_yaw_t = y1
			pitch = p1
			_pitch_t = p1
			_update_ground()
			span = s1
			_span_t = s1
			_anim = {}
			_apply_span()
			blend = 1.0
			mark_dirty()
			return
		_anim = {"t": 0.0, "dur": secs, "s0": span, "s1": s1, "y0": yaw, "y1": y1, "p0": pitch, "p1": p1, "turn": true}

	## Out of the town until its plan's gone (eased over `secs`; 0: at once).
	func leave_town(secs: float) -> void:
		var s1 := maxf(span_floor() * 2.0, span_at_ppm(page._plan.fit_ppm() / PlanetMapPage.PLAN_FROM) * 1.5)
		if secs <= 0.0:
			span = maxf(span, s1)
			_span_t = span
			_anim = {}
			blend = 0.0
			town = ""
			_apply_span()
			mark_dirty()
			return
		_anim = {"t": 0.0, "dur": secs, "s0": span, "s1": maxf(span, s1), "turn": false}

	## From the plan (zoomed out past it): the view over `d` at its zoom (`ppm`, eased to `ppm_to`).
	func take_over(d: Vector3, p: float, p_to: float) -> void:
		var y1 := yaw + wrapf(atan2(d.x, d.z) - yaw, -PI, PI)
		yaw = y1
		_yaw_t = y1
		pitch = -asin(clampf(d.y, -1.0, 1.0))
		_pitch_t = pitch
		_update_ground()
		span = span_at_ppm(p)
		_span_t = span_at_ppm(p_to)
		_anim = {}
		_carry = 1.0
		_apply_span()
		_place_camera()
		_view_changed()
		mark_dirty()

	func _process(delta: float) -> void:
		if is_visible_in_tree() and _sh != null:
			# Someone else's jump (fit, turn_to with a distance, snap_to): the span from it.
			if absf(dist - _set_dist) > _set_dist * 1e-6:
				_update_ground()
				span = _span_of_dist(dist)
				_span_t = span
				_anim = {}
			elif absf(_dist_t - _set_dist) > _set_dist * 1e-6:
				_update_ground()
				_span_t = _span_of_dist(_dist_t)
				_anim = {}
			_update_ground()
			if not _anim.is_empty():
				_anim["t"] += delta
				var u := clampf(_anim["t"] / _anim["dur"], 0.0, 1.0)
				# (linear in the zoom - px a metre: quick down to the town, slow as its plan comes in)
				span = 1.0 / lerpf(1.0 / _anim["s0"], 1.0 / _anim["s1"], smoothstep(0.0, 1.0, u))
				_span_t = span
				if _anim["turn"]:
					var ua := smoothstep(0.0, 0.65, u)   # (turned to it first, then down onto it)
					yaw = lerpf(_anim["y0"], _anim["y1"], ua)
					_yaw_t = yaw
					pitch = lerpf(_anim["p0"], _anim["p1"], ua)
					_pitch_t = pitch
				mark_dirty()
				if u >= 1.0:
					_anim = {}
			else:
				_span_t = clampf(_span_t, span_min(), span_max())
				if absf(log(span / _span_t)) > 0.0005:
					span = exp(lerpf(log(span), log(_span_t), 1.0 - exp(-delta * 10.0)))
					mark_dirty()
				elif span != _span_t:
					span = _span_t
					mark_dirty()
			_apply_span()
		super._process(delta)
		if not is_visible_in_tree() or _sh == null:
			return
		# All the way in over a town you've been in: its plan alone.
		if town != "" and _anim.is_empty() and blend > 0.999 and span <= span_min() * 1.0005 and _span_t <= span_min() * 1.0005:
			page._to_plan()

	## The wheel: nearer or farther; coming in, it turns toward the town
	## you've been in that it's over (else a little toward the cursor).
	func zoom(f: float, at := Vector2(-1, -1)) -> void:
		if _sh == null:
			return
		_anim = {}
		var lo := span_min()
		var want := _span_t * f
		if f < 1.0 and town != "" and want < lo:
			_carry = minf(_carry * lo / want, 20.0)
		elif f > 1.0:
			_carry = 1.0
		_span_t = clampf(want, lo, span_max())
		if f >= 1.0:
			return
		if town != "":
			var u: Vector3 = _town_dir(town)[0]
			var k := clampf((1.0 - f) * 2.5, 0.0, 1.0)
			_pitch_t = lerpf(_pitch_t, -asin(clampf(u.y, -1.0, 1.0)), k)
			_yaw_t = _yaw_t + wrapf(atan2(u.x, u.z) - _yaw_t, -PI, PI) * k
		elif at.x >= 0.0:
			var o := cam.project_ray_origin(at)
			var dir := cam.project_ray_normal(at)
			var b := o.dot(dir)
			var disc := b * b - (o.length_squared() - R * R)
			if disc > 0.0:
				var hit := o + dir * (-b - sqrt(disc))
				var u := hit.normalized()
				var k := (1.0 - f) * 1.2
				_pitch_t = lerpf(_pitch_t, -asin(clampf(u.y, -1.0, 1.0)), k)
				_yaw_t = _yaw_t + wrapf(atan2(u.x, u.z) - _yaw_t, -PI, PI) * k

	## The keys and the pad: their zoom through zoom(), their turn as slow as the view's near.
	func _controls(delta: float) -> void:
		var d0 := _dist_t
		var y0 := _yaw_t
		var p0 := _pitch_t
		var mn := min_dist
		min_dist = 1e-4
		super._controls(delta)
		min_dist = mn
		if _dist_t != d0:
			var f := _dist_t / d0
			_dist_t = d0
			zoom(f)
		if _yaw_t != y0 or _pitch_t != p0:
			_anim = {}
			var k := clampf(span / _tan() / (R * 1.6), 0.0002, 1.0)
			_yaw_t = y0 + (_yaw_t - y0) * k
			_pitch_t = p0 + (_pitch_t - p0) * k

	## (A double click flies to a mark: the globe turns to it - it never leaves the middle.)
	func fly_to(at: Vector3, d := -1.0) -> void:
		if at == Vector3.ZERO:
			super.fly_to(at, d)
		else:
			turn_to(at, d)

	func fit(now := false) -> void:
		if now:
			snap_to(Vector3.ZERO, R * 2.7)
		else:
			fly_to(Vector3.ZERO, R * 2.7)

	## Turns the globe to put `d` (planet-local) before you; `d_to`: how near.
	func turn_to(d: Vector3, d_to := -1.0) -> void:
		var u := d.normalized()
		_anim = {}
		_pitch_t = -asin(clampf(u.y, -1.0, 1.0))
		_yaw_t = yaw + wrapf(atan2(u.x, u.z) - yaw, -PI, PI)
		_focus_t = Vector3.ZERO
		if d_to > 0.0:
			_dist_t = clampf(d_to, min_dist, max_dist)

	func centre_on_you() -> void:
		var o: Dictionary = all.get("you", all.get("ship", {}))
		if not o.is_empty():
			turn_to(o["dir"], R * 1.6)

	func look_at_selected() -> void:
		if all.has(selected_key):
			turn_to(all[selected_key]["dir"], minf(_dist_t, R * 1.5))

	func cycle_order() -> Array:
		return marks.keys()

	func cycle(d := 1) -> void:
		var keys := cycle_order()
		if keys.is_empty():
			return
		var i := keys.find(selected_key)
		var k: String = keys[wrapi(i + d, 0, keys.size())] if i >= 0 else keys[0]
		select(k)
		turn_to(all[k]["dir"])

	func clicked(key: String, _add: bool) -> void:
		if key == "":
			return
		select(key)
		var o: Dictionary = all[key]
		if o["kind"] == "town" and o["visited"]:
			page.open_plan(key)

	func accept() -> void:
		if all.has(selected_key):
			page.open_plan(selected_key)

	## Dragging turns it (as if you held the ground, near) - no panning off it.
	func pan(rel: Vector2) -> void:
		_turn(rel)

	func _turn(rel: Vector2) -> void:
		_anim = {}
		var k := clampf(span / _tan() / (R * 1.6), 0.0, 1.0)
		var grab := 2.0 * span / maxf(size.y, 8.0) / _ground   # (rad a px: the ground under the cursor follows it)
		_yaw_t -= rel.x * maxf(0.008 * k, grab / maxf(cos(_pitch_t), 0.2))
		_pitch_t = clampf(_pitch_t - rel.y * maxf(0.006 * k, grab), -1.5, 1.5)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion and _drag != "":
			var mm := ev as InputEventMouseMotion
			if mm.position.distance_to(_press) > 4.0 or _moved:
				_moved = true
				_turn(mm.relative)
				accept_event()
				return
		super._gui_input(ev)

	## The picture and the marks over it - near the ground, the marks where
	## they stand on it (as the town's plan has them).
	func _draw() -> void:
		draw_texture_rect(vp.get_texture(), Rect2(Vector2.ZERO, size), false)
		_screen = {}
		_behind = {}
		var w := clampf(1.0 - span / span_floor(), 0.0, 1.0)
		for key in marks:
			var p: Vector3 = marks[key]["pos"]
			if w > 0.0 and marks[key].has("ground"):
				p = p.lerp(marks[key]["ground"], w)
			if cam.is_position_behind(p):
				_behind[key] = true
				continue
			_screen[key] = cam.unproject_position(p)
		draw_overlay()

	func draw_overlay() -> void:
		var font := NeonTheme.heavy_font()
		var fa := 1.0 - smoothstep(0.35, 0.85, blend)   # (the marks giving way to the plan's)
		if _sh != null and not _globe.visible:
			draw_string(font, size * 0.5 - Vector2(80, 0), "Charting the world...", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, NeonTheme.HEAD)
		var taken: Array = []
		var near := dist < R * 1.6
		var order: Array = marks.keys()
		order.sort_custom(func(a, b): return _rank(a) > _rank(b))
		if fa <= 0.01:
			return
		for k in order:
			var o: Dictionary = marks[k]
			var p: Variant = at_screen(k)
			if p == null:
				continue
			var sp: Vector2 = p
			var col: Color = o["color"]
			col.a *= fa
			var white := Color(1, 1, 1, fa)
			var hot: bool = k == selected_key or k == hover_key
			match str(o["kind"]):
				"town":
					var rr := 7.0 if o["city"] else 5.0
					draw_rect(Rect2(sp - Vector2(rr, rr), Vector2(rr, rr) * 2.0), Color(col, 0.95), false, 2.0)
					if o["city"]:
						draw_line(sp + Vector2(-rr, -rr - 4), sp + Vector2(rr, -rr - 4), col, 2.0)
					if o["visited"]:
						draw_rect(Rect2(sp - Vector2(2, 2), Vector2(4, 4)), col)
				"cave", "dungeon":
					draw_arc(sp, 6.0, PI, TAU, 10, col, 2.0)
					draw_line(sp + Vector2(-6, 0), sp + Vector2(6, 0), col, 2.0)
				"camp":
					draw_line(sp + Vector2(-5, -5), sp + Vector2(5, 5), col, 2.0)
					draw_line(sp + Vector2(-5, 5), sp + Vector2(5, -5), col, 2.0)
				"ship":
					draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -9), sp + Vector2(7, 7), sp + Vector2(-7, 7)]), col)
				"you":
					draw_circle(sp, 6.0, white)
					# (your heading: along the ground, as the globe shows it)
					var d: Vector3 = o["dir"]
					var hd: float = o["heading"]
					var f3: Vector3 = (o["north"] as Vector3) * cos(hd) + (o["east"] as Vector3) * sin(hd)
					var ahead: Variant = project((o["pos"] as Vector3) + f3 * R * 0.03)
					if ahead != null and (ahead as Vector2).distance_to(sp) > 0.5:
						draw_line(sp, sp + ((ahead as Vector2) - sp).normalized() * 16.0, white, 2.0)
			if hot:
				_brackets(sp, 12.0, col)
			if k == selected_key or k == hover_key or o["kind"] in ["town", "you", "ship"] or near:
				if fa >= 0.99:
					tag(sp + Vector2(0, -12), str(o["name"]), 15, col, taken, font)
				else:
					_fading_tag(sp + Vector2(0, -12), str(o["name"]), col, taken, font, fa)

	## A name tag (as tag()) fading out, its outline with it: the plan's names coming in instead.
	func _fading_tag(at: Vector2, text: String, col: Color, taken: Array, font: Font, a: float) -> void:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var r := Rect2(at - Vector2(w * 0.5, 15), Vector2(w, 18))
		var pad := r.grow_individual(8.0, 2.0, 8.0, 2.0)
		for q: Rect2 in taken:
			if q.intersects(pad):
				return
		taken.append(r)
		draw_string_outline(font, r.position + Vector2(0, 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.85 * a))
		draw_string(font, r.position + Vector2(0, 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)

	func _rank(k: String) -> int:
		if k == selected_key:
			return 9
		return {"you": 5, "ship": 4, "town": 3, "dungeon": 2, "cave": 2, "camp": 1}.get(all[k]["kind"], 0)

	func _brackets(p: Vector2, r: float, col: Color) -> void:
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var c := p + Vector2(sx, sy) * r
				draw_line(c, c - Vector2(sx * 5.0, 0), col, 2.0)
				draw_line(c, c - Vector2(0, sy * 5.0), col, 2.0)


# --- A town's plan ---------------------------------------------------------------------

## A town from above (its plan - bake_plan's picture), north up: its places
## named, you on it. Coming in on the globe it's laid over it where the town
## is (follow_globe: the globe's north and scale), `alpha` of it - its labels
## coming last; all in (`full`), it's its own: the wheel zooms (eased, as the
## globe's), dragging pans, a middle click fits it; zoomed out past the whole
## town, back to the globe (PlanetMapPage.plan_out) the same way.
class TownPlan extends Control:
	var page: Node
	var o := {}                  # the town's mark (PlanetMapPage.gather)
	var key := ""                # (its plan's - PlanetMapPage._plans)
	var t := {}                  # the planet (target())
	var full := false            # (the plan alone: the globe zoomed all the way in)
	var alpha := 1.0             # (how much of it shows over the globe)
	var _frame := Transform3D.IDENTITY
	var _rot := 0.0              # (the plan turned: north up)
	var _north := 0.0            # (its turn north up, at the town)
	var _ppm := 2.0              # zoom: px a metre (eased to _ppm_t)
	var _ppm_t := 2.0
	var _centre := Vector2.ZERO  # the middle of the view (town-local x, z)
	var _anchor := Vector2.ZERO  # (the zoom's: the screen point kept on the same ground)
	var _anchor_w := Vector2.ZERO
	var _drag := false
	var _rect := Rect2()

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		clip_contents = true
		texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func show_town(mark: Dictionary, k: String, planet_t: Dictionary) -> void:
		o = mark
		key = k
		t = planet_t
		var s: Dictionary = o["site"]
		_frame = CosmosTown.frame(s, float(t["radius"]))
		var n := _frame.basis.inverse() * Vector3.UP   # (north, in the town's own frame)
		var n2 := Vector2(n.x, n.z)
		_north = -PI * 0.5 - n2.angle() if n2.length() > 0.01 else 0.0
		_rot = _north
		_rect = PlanetMapPage.plan_rect(str(s["kind"]))
		_centre = _rect.get_center()
		_ppm = fit_ppm()
		_ppm_t = _ppm

	## The zoom showing the whole town (north up).
	func fit_ppm() -> float:
		var sz: Vector2 = size if size.x > 10.0 else (page._view.size if page and page._view.size.x > 10.0 else Vector2(880, 590))
		var c := absf(cos(_north))
		var sn := absf(sin(_north))
		var w := maxf(_rect.size.x * c + _rect.size.y * sn, 1.0)   # (its box, turned north up)
		var h := maxf(_rect.size.x * sn + _rect.size.y * c, 1.0)
		return minf((sz.x - 40.0) / w, (sz.y - 70.0) / h)

	## The whole town in view (eased).
	func fit() -> void:
		_anchor = size * 0.5
		_anchor_w = _rect.get_center()
		_ppm_t = fit_ppm()
		_centre = _anchor_w
		queue_redraw()

	## Laid over the globe `v` as it shows the town now: under its middle, its
	## north, its scale; `a` of it shown.
	func follow_globe(v: Node, a: float) -> void:
		full = false
		alpha = a
		mouse_filter = MOUSE_FILTER_IGNORE
		var up := _frame.basis.inverse() * (v.cam.transform.basis.y as Vector3)
		_rot = -PI * 0.5 - Vector2(up.x, up.z).angle() if Vector2(up.x, up.z).length() > 0.01 else _north
		var g := _frame.affine_inverse() * ((v.view_dir() as Vector3) * _frame.origin.length())
		_centre = Vector2(g.x, g.z)
		_ppm = v.ppm()
		_ppm_t = _ppm
		queue_redraw()

	## All in: the plan alone from here, at `p` px a metre (the wheel's zoom past it: `carry`).
	func enter(p: float, carry: float) -> void:
		full = true
		alpha = 1.0
		mouse_filter = MOUSE_FILTER_STOP
		_ppm = p
		_ppm_t = clampf(p * carry, p, 24.0)
		_anchor = size * 0.5
		_anchor_w = _centre
		queue_redraw()

	## The middle of the view, as a direction (planet-local).
	func centre_dir() -> Vector3:
		return (_frame * Vector3(_centre.x, 0.0, _centre.y)).normalized()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		if full and absf(log(_ppm / _ppm_t)) > 1e-4:
			_ppm = exp(lerpf(log(_ppm), log(_ppm_t), 1.0 - exp(-delta * 10.0)))
			if absf(log(_ppm / _ppm_t)) <= 1e-4:
				_ppm = _ppm_t
			_centre = _anchor_w - (_anchor - size * 0.5).rotated(-_rot) / _ppm
			queue_redraw()
		elif UI.redraw_due(self, 6.0):
			queue_redraw()

	## Town-local (x, z) -> the screen.
	func to_screen(p: Vector2) -> Vector2:
		return size * 0.5 + ((p - _centre) * _ppm).rotated(_rot)

	func from_screen(s: Vector2) -> Vector2:
		return ((s - size * 0.5).rotated(-_rot) / _ppm) + _centre

	func _draw() -> void:
		var a := 1.0 if full else alpha
		var bg := 1.0 if full else smoothstep(0.5, 1.0, a)   # (the globe round the town goes last)
		if bg > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, bg))
		var font := NeonTheme.heavy_font()
		var tex := PlanetMapPage.plan_texture(key)
		if tex == null:
			if full:
				draw_string(font, size * 0.5 - Vector2(90, 0), "Drawing the town's plan...", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, NeonTheme.HEAD)
			return
		draw_set_transform(to_screen(_rect.position), _rot, Vector2.ONE * _ppm / PlanetMapPage.PLAN_PPM)
		draw_texture(tex, Vector2.ZERO, Color(1, 1, 1, a))
		draw_set_transform(Vector2.ZERO)
		var s: Dictionary = o["site"]
		# The places, named (they come in after the buildings).
		var taken: Array = []
		var la := 1.0 if full else smoothstep(0.3, 0.8, a)
		if la > 0.01:
			var fs := 15 if _ppm < 4.0 else 17
			for p in CosmosTown.places(str(s["kind"])):
				var at := to_screen(Vector2((p[2] as Vector3).x, (p[2] as Vector3).z))
				var people: bool = p[0] in ["vendor", "courier", "pilot"]
				var col := Color(NeonTheme.INFO if people else NeonTheme.HEAD, la)
				if people:
					draw_circle(at, 5.0, col)
				else:
					draw_rect(Rect2(at - Vector2(5, 5), Vector2(10, 10)), col, false, 2.0)
				_label(at + Vector2(9, 5), str(p[1]), fs, col, taken, font)
		# You, and your ship (the globe's marks give way to these).
		var ya := 1.0 if full else smoothstep(0.35, 0.85, a)
		var c: Node = page.cosmos()
		var node: Node3D = t.get("node")
		if c and node and ya > 0.01:
			var info := Color(NeonTheme.INFO, ya)
			var white := Color(1, 1, 1, ya)
			if c.ship and is_instance_valid(c.ship):
				var sp3: Vector3 = _frame.affine_inverse() * node.to_local(c.ship.global_position)
				if absf(sp3.y) < 400.0:
					var sp := to_screen(Vector2(sp3.x, sp3.z))
					draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -9), sp + Vector2(7, 7), sp + Vector2(-7, 7)]), info)
					_label(sp + Vector2(10, 5), "Your ship", 15, info, taken, font)
			if c.walker and c.walker.planet == node:
				var wl: Vector3 = _frame.affine_inverse() * node.to_local(c.walker.global_position)
				var wp := to_screen(Vector2(wl.x, wl.z))
				var f: Vector3 = _frame.basis.inverse() * (node.global_basis.inverse() * (c.walker.facing as Vector3))
				var dir := Vector2(f.x, f.z).normalized().rotated(_rot)
				draw_circle(wp, 6.0, white)
				draw_line(wp, wp + dir * 16.0, white, 2.0)
				_label(wp + Vector2(10, 5), "You", 15, white, taken, font)
		# The town's name, north, the scale.
		var ta := 1.0 if full else smoothstep(0.7, 1.0, a)
		if ta <= 0.01:
			return
		var head := Color(NeonTheme.HEAD, ta)
		var text := Color(NeonTheme.TEXT, ta)
		var title := str(o["town"]).to_upper() + ("  -  CITY" if o["city"] else "  -  VILLAGE")
		draw_string_outline(font, Vector2(16, 30), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 4, Color(0, 0, 0, 0.85 * ta))
		draw_string(font, Vector2(16, 30), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, head)
		var nc := Vector2(size.x - 34, 40)
		var nd := Vector2.UP.rotated(_rot - _north)   # (north: up, unless the globe's turned it a little)
		draw_colored_polygon(PackedVector2Array([nc + nd * 16.0, nc + nd.rotated(2.5) * 9.0, nc + nd.rotated(-2.5) * 9.0]), head)
		draw_string(font, nc + Vector2(-6, 26), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, head)
		var m := 50.0 if _ppm < 3.0 else (20.0 if _ppm < 8.0 else 10.0)
		if _ppm < 1.0:
			m = 100.0 if _ppm > 0.5 else 200.0
		var b0 := Vector2(16, size.y - 20)
		draw_line(b0, b0 + Vector2(m * _ppm, 0), text, 2.0)
		for x in [0.0, m * _ppm]:
			draw_line(b0 + Vector2(x, -5), b0 + Vector2(x, 0), text, 2.0)
		draw_string(font, b0 + Vector2(m * _ppm + 8, 5), "%d m" % int(m), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, text)

	func _label(at: Vector2, text: String, fs: int, col: Color, taken: Array, font: Font) -> void:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := Rect2(at - Vector2(0, fs), Vector2(w, fs * 1.2))
		for q: Rect2 in taken:
			if q.intersects(r):
				r.position.y += fs * 1.25   # (one under the other)
		taken.append(r)
		draw_string_outline(font, r.position + Vector2(0, fs), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85 * col.a))
		draw_string(font, r.position + Vector2(0, fs), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	## The wheel (eased, toward the cursor); out past the whole town: the globe again.
	func zoom(f: float, at := Vector2(-1, -1)) -> void:
		if not full:
			return
		_anchor = at if at.x >= 0.0 else size * 0.5
		_anchor_w = from_screen(_anchor)
		var want := _ppm_t * f
		if f < 1.0 and want < fit_ppm() * 0.999:
			page.plan_out(_ppm, want)
			return
		_ppm_t = minf(want, 24.0)

	func _gui_input(ev: InputEvent) -> void:
		if not full:
			return
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom(1.0 / 0.85, mb.position)
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom(0.85, mb.position)
			elif UI.middle_click(self, mb):
				fit()
			elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
				_drag = mb.pressed
			accept_event()
		elif ev is InputEventMouseMotion and _drag:
			_centre -= ((ev as InputEventMouseMotion).relative).rotated(-_rot) / _ppm
			_anchor_w = from_screen(_anchor)
			queue_redraw()
			accept_event()

	func _input(ev: InputEvent) -> void:
		if not full or not is_visible_in_tree() or UI.esc_menu_open():
			return
		if ev is InputEventKey and ev.pressed and not ev.echo:
			match (ev as InputEventKey).keycode:
				KEY_EQUAL, KEY_KP_ADD, KEY_PAGEUP:
					zoom(1.25)
				KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN:
					zoom(0.8)
				KEY_HOME, KEY_BACKSPACE:
					page.close_plan()
				_:
					return
			get_viewport().set_input_as_handled()
