extends RefCounted
## A planet surface built from a terrain tile set (pdata "tiles": a SETS key -
## "fo" the forest sheet external/images/forest_terrain_tile_set.png, cut to
## data/sprites/tile_fo_*; "ic" the ice sheet, tile_ic_*; "vo" the volcanic sheet,
## tile_vo_*; "gg" the gas giants'
## metal platforms, tile_gg_*): Greek ground in 1980s anime style. Pieces are named with their set ("fo_grass"); SETS
## gives each set's piece for every role the builder needs. The ground is in
## LEVELS: flat tiles one level above another, with limestone cliff blocks
## where a level ends and ramps between levels. PlanetSurface uses it instead
## of the procedural ground (SurfaceTerrain's heights still decide the shape).
##
## Per tile: level (0..), ramp (0 none, else the way it rises: RAMP_DIRS), the
## ground look. Walking: only between tiles on the same level, or up / down a
## ramp (step_ok) - the cliffs are walls. What stands on a tile is drawn
## (level - the plots' level) * LEVEL_PX higher (lift).

const LEVEL_PX := 39.0           # one level up (the sheet's 54 px cliff face, scaled)
const SCALE := 128.0 / 176.0     # sheet tiles are 176 px wide; the game's 128
const TERRACE := 0.15            # height (terrain units) per level
## Ramp directions (grid steps): 1 rises toward the top-right of the screen,
## 2 top-left, 3 bottom-left, 4 bottom-right.
const RAMP_DIRS := [Vector2i.ZERO, Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]
const RAMP_PIECES := ["", "ramp_ne", "ramp_nw", "ramp_sw", "ramp_se"]
const MARGIN := 0.16             # (tiles) how close to a cliff edge you can walk

## Each set's pieces by role (names without the set prefix): the plain ground,
## its variants by noise, the ground of a terrain kind (`kinds`), high ground,
## ground by the water, deep and shallow water; the ramps' stone faces; what
## grows: dense kinds (`woods`: trees, shrubs), elsewhere trees, shrubs, rocks
## and ruins (with their chances).
const SETS := {
	"fo": {"base": "grass", "flowers": "grass_flowers", "dry": "grass_dry", "high": "limestone_ground",
		"shore_ground": "sand", "deep": "sea", "shallow": "shallows", "kinds": {"forest": "forest_floor"},
		"stone": Color(0.8, 0.7, 0.6),
		"woods": ["forest"], "wood_trees": ["holm_oak", "aleppo_pine", "plane_tree", "cypress", "olive_old"], "wood_shrubs": ["myrtle", "oleander"],
		"trees": ["olive", "olive_young", "cypress", "cypress_pair"], "shrubs": ["oleander", "myrtle", "lavender"],
		"rocks": ["boulder", "boulders"], "ruins": ["column_fallen", "column_stump", "stone_wall"],
		"chances": [0.05, 0.05, 0.015, 0.003]},
	"ic": {"base": "snow", "flowers": "snow_sparkle", "dry": "snow_drifts", "high": "rock_ground",
		"shore_ground": "snow_plain", "deep": "deep_ice", "shallow": "frozen_lake", "kinds": {"ice": "snow_ice"},
		"stone": Color(0.62, 0.8, 0.94),
		"woods": [], "wood_trees": [], "wood_shrubs": [],
		"trees": ["snow_pine", "dead_tree", "crystals", "crystal_spire"], "shrubs": ["frost_bush", "frost_shrub", "crystal_sprout"],
		"rocks": ["ice_rock"], "ruins": ["column_stump", "column", "column_fallen", "capital", "arch", "colonnade", "ruined_wall"],
		"chances": [0.04, 0.05, 0.015, 0.006]},
	# The volcanic planet: basalt, ash and sulphur, magma for water, fumaroles,
	# obsidian spires and basalt columns, soot-blackened Greek ruins.
	"vo": {"base": "basalt", "flowers": "basalt_cracks", "dry": "ash", "high": "rock_ground",
		"shore_ground": "ash_flat", "deep": "magma_lake", "shallow": "magma", "kinds": {"sand": "ash", "crater": "sulphur"},
		"stone": Color(0.36, 0.3, 0.32),
		"woods": [], "wood_trees": [], "wood_shrubs": [],
		"trees": ["obsidian_spire", "charred_tree", "basalt_columns", "fumarole"], "shrubs": ["sulphur_crystals", "lava_rock", "magma_vent"],
		"rocks": ["basalt_boulder"], "ruins": ["column_stump", "column", "column_fallen", "capital", "arch", "colonnade", "ruined_wall"],
		"chances": [0.03, 0.04, 0.02, 0.005]},
	# Gas giants: metal platforms hovering in the clouds. "sky": the water is
	# open air - nothing drawn there (the background shows), every platform
	# stands at level 1 or more and shows its underside toward it. "alts":
	# a second drawing of a role (the second sheet), used about half the time.
	"gg": {"base": "deck", "flowers": "deck_lit", "dry": "deck_rusty", "high": "deck_heavy",
		"shore_ground": "edge_hazard", "deep": "", "shallow": "", "kinds": {"solar": "deck_solar", "grating": "deck_grating"},
		"alts": {"deck": "deck_b", "deck_lit": "deck_lit_b", "deck_rusty": "deck_rusty_b", "deck_heavy": "deck_heavy_b",
			"deck_solar": "deck_solar_b", "deck_grating": "deck_grating_b", "edge_hazard": "edge_hazard_b"},
		"sky": true, "stone": Color(0.42, 0.47, 0.55),
		"woods": [], "wood_trees": [], "wood_shrubs": [],
		"trees": ["antenna", "radar", "vent_stack", "fuel_tank", "crane", "cooling_tower", "beacon", "pipes",
			"antenna_b", "radar_b", "vent_stack_b", "fuel_tank_b", "crane_b", "cooling_tower_b", "beacon_b", "pipes_b"],
		"shrubs": ["crate", "barrels", "machinery", "railing", "lamp_post", "robot", "crate_b", "barrels_b", "machinery_b", "railing_b", "lamp_post_b", "robot_b"],
		"rocks": ["containers", "containers_b", "scrap_heap", "scrap_heap_b"], "ruins": ["container_fallen", "container_fallen_b"],
		"chances": [0.02, 0.035, 0.01, 0.006]},
}
## Pieces every set has, by these names.
const COMMON := ["shore_left", "shore_right", "shore_corner", "block_corner", "block_left", "block_right",
	"ramp_ne", "ramp_nw", "ramp_sw", "ramp_se", "rim_l", "rim_r", "rim_lr"]
## Rims (made, like the ramps): the plain ground with a lip drawn along its
## back edges, for a ledge whose ground drops away behind it - the cliff faces
## away from you there, so without it a step up looks like flat ground.
## rim_l: the top-left edge (the tile at grid -x is lower), rim_r: the top-right
## edge (grid -y), rim_lr: both.
const RIMS := ["rim_l", "rim_r", "rim_lr"]


## A set's piece for a role ("base", "deep" ...) or a common piece's name:
## "fo_grass" - or "" when the set draws nothing for the role (a sky set's water).
static func pc(set_: String, role: String) -> String:
	var s: Dictionary = SETS.get(set_, SETS["fo"])
	var name := str(s.get(role, role))
	return (set_ + "_" + name) if name != "" else ""


## Every piece a set's ground uses (full names).
static func ground_pieces(set_: String) -> Array:
	var out := []
	for role in ["base", "flowers", "dry", "high", "shore_ground", "deep", "shallow"] + COMMON:
		var n := pc(set_, role)
		if n != "":
			out.append(n)
	for v in SETS[set_]["kinds"].values():
		out.append(set_ + "_" + str(v))
	for v in SETS[set_].get("alts", {}).values():
		out.append(set_ + "_" + str(v))
	return out


## The set's water is open sky (nothing drawn; platforms show their undersides toward it).
static func is_sky(set_: String) -> bool:
	return SETS.get(set_, {}).get("sky", false)


## A tile set's piece name ("fo_olive"): scenery drawn from its texture.
static func is_piece(kind: String) -> bool:
	return kind.length() > 3 and kind[2] == "_" and SETS.has(kind.substr(0, 2))


## Levels from heights (worker thread): water and beaches at level 0, the land
## in steps of TERRACE above the water, smoothed (no single-tile pits or spikes).
static func levels(n: int, height: PackedFloat32Array, walk: PackedByteArray, water_top: float) -> PackedByteArray:
	var lv := PackedByteArray()
	lv.resize(n * n)
	for k in n * n:
		lv[k] = 0 if walk[k] == 0 else clampi(floori(maxf(0.0, height[k] - water_top - 0.03) / TERRACE), 0, 20)
	# Each tile to the commonest level round it (3 x 3), twice: tidy ledges.
	var tmp := lv.duplicate()
	var cnt := PackedInt32Array()
	cnt.resize(256)
	var offs := PackedInt32Array([-n - 1, -n, -n + 1, -1, 0, 1, n - 1, n, n + 1])
	for pass_ in 2:
		for i in range(1, n - 1):
			for j in range(1, n - 1):
				var k := i * n + j
				if walk[k] == 0:
					continue
				# (the 9 levels round it, counted in a small array: no allocations)
				var best := lv[k]
				var best_n := 0
				for o in offs:
					var q := k + o
					if walk[q] == 0:
						continue
					var v := lv[q]
					cnt[v] += 1
					if cnt[v] > best_n:
						best_n = cnt[v]
						best = v
				for o in offs:
					cnt[lv[k + o]] = 0
				tmp[k] = best if best_n >= 5 else lv[k]
		lv = tmp.duplicate()
	return lv


## The look of a flat tile: the base ground and its variants by noise, a
## terrain kind's own ground (forest floor, blue ice), rock up high, sand /
## plain snow by the water.
static func ground_piece(set_: String, t_kind: String, lvl: int, near_water: bool, noise: float, noise2: float) -> String:
	var name := _ground_role(set_, t_kind, lvl, near_water, noise, noise2)
	# (a second drawing of it, by a hash of the noise: about half the tiles)
	var alts: Dictionary = SETS[set_].get("alts", {})
	var base := name.substr(3)
	if alts.has(base) and fmod(absf(noise * 37.1 + noise2 * 91.7), 1.0) > 0.5:
		return set_ + "_" + str(alts[base])
	return name


static func _ground_role(set_: String, t_kind: String, lvl: int, near_water: bool, noise: float, noise2: float) -> String:
	if near_water and (lvl == 0 or is_sky(set_)):
		return pc(set_, "shore_ground")
	if lvl >= 6 and noise2 > 0.2:
		return pc(set_, "high")
	var kinds: Dictionary = SETS[set_]["kinds"]
	if kinds.has(t_kind) and noise2 > -0.1:
		return set_ + "_" + str(kinds[t_kind])
	if noise > 0.45:
		return pc(set_, "flowers")
	if noise < -0.5:
		return pc(set_, "dry")
	return pc(set_, "base")


## Flat ground pieces: drawn as seamless diamonds (their painted outline and
## earth edge cut away, a hair bigger than a tile so neighbours overlap).
const FLAT := ["grass", "grass_flowers", "grass_dry", "forest_floor", "limestone_ground", "path_straight",
	"path_corner", "path_paved", "sand", "sand_grass", "sea", "shallows", "shore_left", "shore_right", "shore_corner", "river",
	"snow", "snow_sparkle", "snow_drifts", "snow_packed", "rock_ground", "deep_ice", "frozen_lake", "snow_plain", "snow_ice", "stream",
	"basalt", "basalt_cracks", "ash", "sulphur", "magma_lake", "magma", "ash_flat", "pahoehoe", "lava_river",
	"deck", "deck_lit", "deck_rusty", "deck_solar", "deck_stripes", "deck_stripes_corner", "deck_grating", "deck_heavy", "edge_hazard", "edge_rings",
	"deck_b", "deck_lit_b", "deck_rusty_b", "deck_solar_b", "deck_stripes_b", "deck_stripes_corner_b", "deck_grating_b", "deck_heavy_b", "edge_hazard_b", "edge_rings_b"]
const FLAT_SIZE := Vector2i(132, 66)
const INSET := 0.1               # of the diamond's half-size: the outline cut away

## The scaled texture of a piece, and where its top corner sits (texture px).
static var _scaled := {}
static var _images := {}         # their images (kept: the ground's atlas is packed from them - tile_set)
static var _src := {}            # name -> the sheet piece's Image, fetched on the main thread (prefetch)
static var _src_ph := {}         # name -> true: that Image is a placeholder (its picture not in yet)
## Pieces made from placeholders (a sheet piece's picture not in yet - the
## ground drawn at once, never waited for): name -> true. refresh() makes them
## again from the real pictures when they're in, in place (the same textures).
static var _ph := {}
## Ground atlases packed with placeholder pieces in: [atlas ImageTexture, names].
static var _sets: Array = []
static var _sets_lock := Mutex.new()
static var _busy := false
## Moves on when a ground atlas took its real pictures (ProcArt): the surfaces
## redraw their ground's pictures (GroundChunks).
static var atlas_serial := 0


## (main thread) The pieces' pictures, so worker threads can make the tiles -
## never waited for: a picture not in yet comes as its placeholder (ProcArt).
static func prefetch(names: Array) -> void:
	for n in names:
		var s := str(n)
		if not _src.has(s) and not s.substr(3).begins_with("ramp_") and not s.substr(3) in RIMS:
			_src[s] = MinoanTiles.image(s)
			if MinoanTiles.is_placeholder(s):
				_src_ph[s] = true

## A set's cached pieces decoded ahead on a worker thread (predecode) - the
## first draw of a planet's scenery only makes their textures (decoding a
## dozen PNGs there was ~6 ms of the landing's longest frame).
static var _decoded := {}
static var _decoded_lock := Mutex.new()

## (worker thread) Decodes every cached piece of set `set_` not decoded yet.
static func predecode(set_: String) -> void:
	var dir := DirAccess.open(CACHE_DIR)
	if dir == null:
		return
	var prefix := "v%d_%s_" % [CACHE_VERSION, set_]
	for f in dir.get_files():
		if not (f.begins_with(prefix) and f.ends_with(".png")):
			continue
		var name := f.trim_prefix("v%d_" % CACHE_VERSION).trim_suffix(".png")
		_decoded_lock.lock()
		var have := _decoded.has(name)
		_decoded_lock.unlock()
		if have:
			continue
		var img := _cache_load(name)
		if img:
			_decoded_lock.lock()
			_decoded[name] = img
			_decoded_lock.unlock()


static func piece_texture(name: String) -> Texture2D:
	if _scaled.has(name):
		return _scaled[name]
	var made := _piece_image(name)
	var img: Image = made[0]
	if made[1]:
		_sets_lock.lock()
		_ph[name] = true
		_sets_lock.unlock()
	if img:
		_images[name] = img
	_scaled[name] = ImageTexture.create_from_image(img) if img else null
	return _scaled[name]


## The sheet pieces a piece is made from (ramps and rims: the set's plain
## ground; a block: itself, its top the plain ground).
static func _sources_of(name: String) -> Array:
	var b := pc(name.substr(0, 2), "base")
	var base := name.substr(3)
	if base.begins_with("ramp_") or base in RIMS:
		return [b]
	if base.begins_with("block_") and b != name:
		return [name, b]
	return [name]


## The set's plain ground's image (`over`: pieces made again, not stored yet).
static func _base_image(set_: String, over: Dictionary) -> Image:
	var b := pc(set_, "base")
	if over.has(b):
		return over[b]
	piece_texture(b)
	return _images.get(b)


## A piece's image, made: [Image, made from a placeholder?]. Saved to the tile
## cache only when made from the real pictures.
static func _piece_image(name: String, over := {}) -> Array:
	var set_ := name.substr(0, 2)
	var base := name.substr(3)       # (the piece's name in its set)
	var b := pc(set_, "base")
	var base_ph := func() -> bool:
		_sets_lock.lock()
		var on := _ph.has(b) and not over.has(b)
		_sets_lock.unlock()
		return on or _src_ph.has(b)
	if over.is_empty():
		_decoded_lock.lock()
		var pre: Image = _decoded.get(name)
		_decoded.erase(name)
		_decoded_lock.unlock()
		var cached: Image = pre if pre else _cache_load(name)
		if cached:
			return [cached, false]
	if base.begins_with("ramp_"):
		var r := RAMP_PIECES.find(base)
		var img := _ramp_image(set_, r, over) if r > 0 else null
		var ph: bool = base_ph.call()
		if img and not ph:
			_cache_save(name, img)
		return [img, ph]
	if base in RIMS:
		var rim := _rim_image(set_, base, over)
		var ph: bool = base_ph.call()
		if not ph:
			_cache_save(name, rim)
		return [rim, ph]
	var src: Image = _src.get(name)
	if src == null:
		src = MinoanTiles.image(name)
	if src == null:
		return [null, false]
	var ph := _src_ph.has(name)
	var img := src.duplicate()
	if img.is_compressed():
		img.decompress()
	if base in FLAT:
		img = _seamless(img)
	else:
		img.resize(maxi(1, roundi(img.get_width() * SCALE)), maxi(1, roundi(img.get_height() * SCALE)), Image.INTERPOLATE_LANCZOS)
		if base.begins_with("block_"):
			# The same ground as the plain ground on its top (one lawn up to the cliff's edge).
			img.convert(Image.FORMAT_RGBA8)
			var top := _base_image(set_, over)
			img.blend_rect(top, Rect2i(Vector2i.ZERO, top.get_size()), Vector2i(roundi(img.get_width() * 0.5 - top.get_width() * 0.5), -1))
			ph = ph or base_ph.call()
	if not ph:
		_cache_save(name, img)
	return [img, ph]


## Pieces made from placeholders whose pictures are all in now: made again (on
## a worker thread), their textures given the new images (the same textures -
## whatever draws them shows the real thing), and every ground atlas left with
## no placeholder in it packed again in place. True if an atlas changed (the
## ground's pictures want redrawing). Main thread; await it.
static func refresh(tree: SceneTree) -> bool:
	if _busy or _ph.is_empty():
		return false
	var art: Node = tree.root.get_node_or_null("ProcArt")
	if art == null:
		return false
	var redo := []
	_sets_lock.lock()
	var phs: Array = _ph.keys()
	_sets_lock.unlock()
	for n in phs:
		var ok := true
		for s in _sources_of(n):
			if not art.is_in(MinoanTiles.PREFIX + s):
				ok = false
				break
		if ok:
			redo.append(n)
	if redo.is_empty():
		return false
	_busy = true
	# (the plain ground first: ramps, rims and blocks are made from it)
	redo.sort_custom(func(a, b_): return a == pc(a.substr(0, 2), "base") and b_ != pc(b_.substr(0, 2), "base"))
	for n in redo:
		for s in _sources_of(n):
			if _src_ph.has(s):
				MinoanTiles.upgrade(s)
				_src[s] = MinoanTiles.image(s)
				_src_ph.erase(s)
	var over := {}
	var task := WorkerThreadPool.add_task(func():
		for n in redo:
			var made := _piece_image(n, over)
			if made[0] != null:
				over[n] = made[0], false, "Ground pieces: the real pictures")
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	for n in over:
		_images[n] = over[n]
		_sets_lock.lock()
		_ph.erase(n)
		_sets_lock.unlock()
		var t: Variant = _scaled.get(n)
		if t is ImageTexture:
			(t as ImageTexture).set_image(over[n])
	var changed := false
	_sets_lock.lock()
	var sets := _sets.duplicate()
	_sets_lock.unlock()
	for s in sets:
		var left := false
		_sets_lock.lock()
		for n in s[1]:
			if _ph.has(n):
				left = true
				break
		_sets_lock.unlock()
		if left:
			continue
		_sets_lock.lock()
		_sets.erase(s)
		_sets_lock.unlock()
		var imgs := []
		for n in s[1]:
			imgs.append(_images.get(n) if _scaled.get(n) != null else null)
		var packed := [null]
		var t2 := WorkerThreadPool.add_task(func(): packed[0] = TextureAtlas.pack(imgs)[0], false, "Ground atlas")
		while not WorkerThreadPool.is_task_completed(t2):
			await tree.process_frame
		WorkerThreadPool.wait_for_task_completion(t2)
		if packed[0] != null and is_instance_valid(s[0]):
			(s[0] as ImageTexture).set_image(packed[0])
			changed = true
	_busy = false
	return changed


## The made pieces (scaled, seamless, ramps) are kept in user://tile_cache:
## making them is GDScript pixel work (~0.6 s a set); loading them is quick.
## A cached piece is used while it's newer than its sheet piece (and the
## set's base ground, which ramps and block tops are made from) and was made
## by this CACHE_VERSION.
const CACHE_DIR := "user://tile_cache/"
const CACHE_VERSION := 1

static func _cache_path(name: String) -> String:
	return CACHE_DIR + "v%d_%s.png" % [CACHE_VERSION, name]


static func _sources_time(name: String) -> int:
	var set_ := name.substr(0, 2)
	var base := name.substr(3)
	var t := 0
	for src in [base, str(SETS.get(set_, SETS["fo"])["base"])]:
		var f := "res://data/sprites/tile_%s_%s.png" % [set_, src]
		if FileAccess.file_exists(f):
			t = maxi(t, FileAccess.get_modified_time(f))
	return t


static func _cache_load(name: String) -> Image:
	var path := _cache_path(name)
	if not FileAccess.file_exists(path) or FileAccess.get_modified_time(path) < _sources_time(name):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return img if img and not img.is_empty() else null


static func _cache_save(name: String, img: Image) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	img.save_png(ProjectSettings.globalize_path(_cache_path(name)))


## A flat piece's diamond without its outline: the top diamond (the sheet's
## 2:1, its sides half way down its width), cut INSET inside the edge, then
## scaled to FLAT_SIZE (the corners stay sharp: alpha cut on the scaled image).
static func _seamless(src: Image) -> Image:
	src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var hw := w * 0.5                      # half width = the diamond's half width
	var hh := hw * 0.5                     # half height (2:1)
	var x0 := roundi(hw * INSET)
	var y0 := roundi(hh * INSET)
	var cw := w - 2 * x0
	var ch := roundi(2.0 * hh) - 2 * y0
	var inner := src.get_region(Rect2i(x0, y0, cw, ch))
	inner.resize(FLAT_SIZE.x, FLAT_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var cx := FLAT_SIZE.x * 0.5
	var cy := FLAT_SIZE.y * 0.5
	for y in FLAT_SIZE.y:
		for x in FLAT_SIZE.x:
			var d := absf(x + 0.5 - cx) / cx + absf(y + 0.5 - cy) / cy
			if d > 1.0:
				inner.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d > 0.97:
				var c := inner.get_pixel(x, y)
				c.a *= (1.0 - d) / 0.03
				inner.set_pixel(x, y, c)
	return inner


## A rim piece (RIMS): the plain ground diamond, its back edge(s) drawn as a
## lip - a dark line where it drops, a bright one just inside - so the
## ledge reads from any side.
static func _rim_image(set_: String, which: String, over := {}) -> Image:
	var img: Image = _base_image(set_, over).duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var stone: Color = SETS[set_]["stone"]
	var dark := Color(stone.r * 0.42, stone.g * 0.42, stone.b * 0.48, 1.0)
	var w := img.get_width()
	var h := img.get_height()
	var cx := w * 0.5
	var cy := h * 0.5
	var left := which != "rim_r"
	var right := which != "rim_l"
	for y in int(cy) + 1:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var px := (x + 0.5 - cx) / cx
			var py := (y + 0.5 - cy) / cy
			# (0 at the edge, in units of the half-diamond: ~30 px to the centre)
			var e := INF
			if left and px <= 0.02:
				e = minf(e, 1.0 + px + py)
			if right and px >= -0.02:
				e = minf(e, 1.0 - px + py)
			if e < 0.075:
				img.set_pixel(x, y, Color(dark, c.a))
			elif e < 0.16:
				img.set_pixel(x, y, Color(c.lerp(Color.WHITE, 0.55), c.a))
			elif e < 0.3:
				var k := 1.0 - 0.1 * (0.3 - e) / 0.14
				img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, c.a))
	return img


## A ramp, made to fit the grid: the grass diamond tilted up one level toward
## RAMP_DIRS[r], limestone faces under its exposed front sides. The cell's
## centre (at its low level) is at (66, RAMP_TOP + 32) in the image.
const RAMP_TOP := 44             # px above the diamond's top in the image (one level + a margin)

static func _ramp_image(set_: String, r: int, over := {}) -> Image:
	var grass := _base_image(set_, over)
	var d := Vector2(RAMP_DIRS[r])
	var hgt := LEVEL_PX
	var w := 132
	var h := 66 + RAMP_TOP
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cy := RAMP_TOP + 32.0    # the cell centre's row
	var stone: Color = SETS[set_]["stone"]
	# lit or shaded by the way it faces (light from the upper left)
	var lit := 1.1 if r == 1 or r == 2 else 0.92
	for y in h:
		for x in w:
			var sx := x + 0.5 - 66.0
			var sy := y + 0.5 - cy
			# The top: solve screen = (64 (u - v), 32 (u + v) - hgt (d . (u, v) + 0.5)) for (u, v).
			var a := sx / 64.0
			var den := 64.0 - hgt * (d.x + d.y)
			var v := (sy + hgt * 0.5 - a * (32.0 - hgt * d.x)) / den
			var u := a + v
			if absf(u) <= 0.5 and absf(v) <= 0.5:
				var tx := clampi(roundi(66.0 + (u - v) * 64.0), 0, grass.get_width() - 1)
				var ty := clampi(roundi(33.0 + (u + v) * 32.0), 0, grass.get_height() - 1)
				var c := grass.get_pixel(tx, ty)
				if c.a < 0.5:   # (the seamless diamond's cut edge: its nearest inside colour)
					c = grass.get_pixel(66, 33)
				img.set_pixel(x, y, Color(c.r * lit, c.g * lit, c.b * lit, 1.0))
				continue
			# The front faces (right-front: u = 0.5, left-front: v = 0.5), down to the low level.
			for side in 2:
				var s_: float          # position along the edge
				var uv: Vector2
				if side == 0:
					s_ = 0.5 - sx / 64.0
					uv = Vector2(0.5, s_)
				else:
					s_ = sx / 64.0 + 0.5
					uv = Vector2(s_, 0.5)
				if absf(s_) > 0.5:
					continue
				var base := 32.0 * (uv.x + uv.y)
				var top := base - hgt * clampf(d.dot(uv) + 0.5, 0.0, 1.0)
				if sy >= top and sy <= base:
					var row := floori((base - sy) / 13.0)
					var joint := fmod(sx + row * 17.0, 30.0) < 1.5 or fmod(base - sy, 13.0) < 1.2
					var k := (0.72 if side == 0 else 0.9) * (0.75 if joint else 1.0)
					img.set_pixel(x, y, Color(stone.r * k, stone.g * k, stone.b * k, 1.0))
					break
	return img


## A TileSet with one tile per piece (source id = index in `names`), each
## placed on its cell: flat tiles and blocks by their top corner, ramps by
## their bottom (they're drawn in their own geometry).
## The pieces' images packed into one texture (TextureAtlas):
## [texture, [top-left or null per piece]].
static func _pack(names: Array, texs: Array) -> Array:
	var imgs := []
	for i in names.size():
		var img: Image = _images.get(names[i]) if texs[i] != null else null
		if img == null and texs[i] != null:
			img = (texs[i] as Texture2D).get_image()
		imgs.append(img)
	var packed := TextureAtlas.pack(imgs)
	return [ImageTexture.create_from_image(packed[0]) if packed[0] else null, packed[1]]


static func tile_set(names: Array) -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(128, 64)
	# All the pieces in one atlas texture (each source a region of it): the
	# ground draws in a few batches, not a draw call per change of piece
	# (a texture each: ~550 draw calls on a planet).
	var texs := []
	for n in names:
		texs.append(piece_texture(n))
	var packed := _pack(names, texs)
	var atlas: Texture2D = packed[0]
	var at_pos: Array = packed[1]
	if atlas:
		_sets_lock.lock()
		for n in names:
			if _ph.has(n):   # (packed with placeholders in: packed again, in place, when they're real - refresh)
				_sets.append([atlas, names.duplicate()])
				break
		_sets_lock.unlock()
	for i in names.size():
		var tex: Texture2D = texs[i]
		var src := TileSetAtlasSource.new()
		if tex == null:
			ts.add_source(src, i)
			continue
		if atlas and at_pos[i] != null:
			src.texture = atlas
			src.margins = at_pos[i]
			src.use_texture_padding = false   # (else each source makes its own padded copy: a texture each again; the atlas has PAD)
		else:
			src.texture = tex
		src.texture_region_size = Vector2i(tex.get_width(), tex.get_height())
		src.create_tile(Vector2i.ZERO)
		var td := src.get_tile_data(Vector2i.ZERO, 0)
		var size := Vector2(tex.get_width(), tex.get_height())
		var anchor: Vector2   # (texture px from its top-left) that goes on the cell's point below
		var at: Vector2       # that point, from the cell's centre
		var base := str(names[i]).substr(3)
		if base in FLAT or base in RIMS:
			anchor = size * 0.5            # (the diamond's centre on the cell's)
			at = Vector2.ZERO
		elif base.begins_with("ramp_"):
			anchor = Vector2(66, RAMP_TOP + 32)   # (made to fit: _ramp_image)
			at = Vector2.ZERO
		elif base.begins_with("steps_"):
			anchor = Vector2(size.x * 0.5, size.y)
			at = Vector2(0, 32.0 + 11.0 * SCALE)
		else:
			anchor = Vector2(size.x * 0.5, 0)
			at = Vector2(0, -32)
		# (drawn centred on the cell, minus the origin)
		td.texture_origin = Vector2i((anchor - size * 0.5 - at).round())
		ts.add_source(src, i)
	return ts
