class_name MinoanTiles
## Minoan buildings assembled from the Minoan tile sheets in external/images/
## (drawn from the prompts in external/prompt_templates/), cut into
## data/sprites/tile_<set>_*.png by tools/extract_sprites.py:
##   palace     minoan_palace_tile_sheet.png     (tile_palace_*)
##   wh         minoan_warehouse_tile_sheet.png  (tile_wh_*)
##   xt         minoan_extra_tile_sheet.png      (tile_xt_* - more floors, frescoed and
##              arched walls, statues, fountains, crystals; its walls are drawn one
##              way, the other way is them mirrored)
## Piece names here carry their set ("palace_horns", "wh_crate"), so the
## building styles mix and match pieces from every sheet.
##
## The sheets are drawn in the game's own 2:1 isometric projection, so pieces
## are only scaled, never sheared: a wall piece spans exactly one tile edge
## (64 px). Its walls are a little squatter than a game storey (WALL_H), so
## each wall is topped with the upper courses of its sheet's plain stone wall,
## at the same scale. Walls facing either way use the sheet's own left / right
## pieces (wallx_* run down-right, wally_* up-right). Floor and roof tiles
## take the pieces' top faces (drawn slightly steeper than 2:1: they're
## squashed vertically onto the tile diamond - a uniform scale).
##
## Styles: palace (frescoes, mosaics, red columns), warehouse (slate and
## cream blocks, tech slots, cargo shutters, loading bays, crates, forklifts),
## temple (red plaster, dolphins, gold columns, braziers and a roof garden).

const PREFIX := "tile_"
## Sprite pieces used outside the styles' lists that go in the atlas too (the teleport gates).
const ATLAS_EXTRA := ["xt_portal"]
const RES := 2                       # wall textures: RES x the game's pixels
## Game px per sheet px for standing pieces (a sheet wall's 102 px = one 64 px tile edge).
const PIECE_SCALE := 0.64
## Sheet px of a wall piece's own top cap, hidden under the course above it.
const CAP_CROP := 6
## Each sheet's plain stone wall: tops walls up to a full storey.
const CAP_WALL := {"palace": "stone", "wh": "cream", "spa": "stone", "ath": "stone", "myc": "stone", "ion": "stone", "cyc": "stone"}
## Sheets without a plain wall of their own: whose plain wall tops theirs.
const CAP_FROM := {"xt": "palace"}

## Wall designs are "<set>_<design>" (resolved to <set>_wall<x|y>_<design>);
## doors are cut into the style's "door" wall.
const STYLES := {
	"palace": {"plain": ["palace_bull", "palace_stone", "palace_leapers", "palace_red", "palace_dolphins", "wh_spiral", "palace_stone",
			"xt_warrior", "xt_griffin", "xt_ship", "xt_banner"],
		"window": ["palace_window", "palace_techwindow", "xt_arches"], "door": "palace_stone",
		"floor": ["palace_floor_stone", "palace_floor_stone_b", "palace_floor_slabs", "wh_floor_checker", "xt_floor_plain"],
		"mosaic": ["palace_floor_mosaic_spiral", "palace_floor_mosaic_dolphin", "xt_floor_meander", "xt_floor_sun", "xt_floor_star", "xt_floor_lotus"],
		"roof": ["palace_roof_terrace", "palace_roof_gold", "wh_roof_gold"], "column": "palace_column_red",
		"caps": ["palace_roof_cap", "palace_roof_cap", "palace_dome"], "antenna": "palace_antenna",
		"dome": "palace_dome", "horns": "palace_horns",
		"decor": ["palace_urn_large", "palace_amphora", "palace_olive_tree", "palace_cypress", "palace_lilies", "wh_pithos", "palace_cypress",
			"xt_sphinx", "xt_lion", "xt_fountain", "xt_planter_palm", "xt_rose_arbor", "xt_obelisk"],
		"entrance": ["palace_hologram", "palace_banner", "xt_lion"]},
	"warehouse": {"plain": ["wh_cream", "wh_slate", "wh_spiral", "wh_techslot", "wh_shutter", "wh_bull", "wh_cream", "wh_slate",
			"xt_slit", "xt_portal"],
		"window": ["wh_techwindow"], "door": "wh_cream",
		"floor": ["wh_floor_slate", "wh_floor_slate_worn", "wh_floor_concrete", "wh_floor_slabs", "wh_floor_checker"],
		"mosaic": ["wh_floor_loading", "wh_floor_grating", "wh_floor_tech", "xt_floor_tech_dark", "xt_floor_ring"],
		"roof": ["wh_roof_tech", "wh_roof_solar", "wh_roof_vents", "wh_roof_hatch", "wh_roof_slate"], "column": "wh_pillar",
		"caps": ["wh_roof_cap", "wh_tech_unit", "wh_roof_cap"], "antenna": "wh_antenna",
		"dome": "wh_tech_unit", "horns": "wh_horns",
		"decor": ["wh_crate", "wh_crates_stack", "wh_container", "wh_supply_crates", "wh_forklift", "wh_shelves", "wh_power_cell", "wh_crane", "wh_pithos",
			"xt_crystal_lamp", "xt_pillar_tech"],
		"entrance": ["palace_hologram", "wh_banner"]},
	"temple": {"plain": ["palace_red", "palace_dolphins", "palace_bull", "palace_leapers", "wh_spiral", "palace_red",
			"xt_palm", "xt_sky", "xt_griffin", "xt_warrior"],
		"window": ["palace_window", "xt_arcade", "xt_arches"], "door": "palace_stone",
		"floor": ["palace_floor_stone_b", "palace_floor_slabs", "wh_floor_slabs", "xt_floor_plain"],
		"mosaic": ["palace_floor_mosaic_dolphin", "palace_floor_mosaic_spiral", "xt_floor_waves", "xt_floor_star", "xt_floor_lotus"],
		"roof": ["palace_roof_garden", "palace_roof_skylight", "wh_roof_skylight", "palace_roof_terrace"], "column": "palace_column_gold",
		"caps": ["palace_roof_cap", "palace_dome", "wh_roof_cap"], "antenna": "palace_antenna",
		"dome": "palace_dome", "horns": "wh_horns",
		"decor": ["palace_brazier", "palace_urn_large", "palace_lilies", "palace_cypress", "palace_olive_tree", "wh_pithos",
			"xt_crystal_shrine", "xt_crystal_lamp", "xt_brazier", "xt_fountain", "xt_obelisk", "xt_rose_arbor"],
		"entrance": ["palace_brazier", "wh_banner", "xt_sphinx"]},
	# --- The other empires' buildings: pieces drawn by tools/empire_tiles.py
	# (data/sprites/tile_<set>_*.png); a planet's buildings use its owner's
	# ("<empire>_<style>", see style() and `culture`).
	"sparta_palace": {"plain": ["spa_stone", "spa_shields", "spa_lambda", "spa_inscription", "spa_stone", "spa_shields"],
		"window": ["spa_window"], "door": "spa_door",
		"floor": ["spa_floor_flags", "spa_floor_flags_b"], "mosaic": ["spa_mosaic_lambda", "spa_mosaic_meander"],
		"roof": ["spa_roof_laconian", "spa_roof_laconian_b"], "column": "spa_column_doric",
		"caps": ["spa_cap_block", "spa_cap_block", "spa_tripod_great"], "antenna": "spa_mast_spear",
		"dome": "spa_tripod_great", "horns": "spa_crown_helmet",
		"decor": ["spa_statue_hoplite", "spa_tripod", "spa_shield_stack", "spa_brazier", "spa_banner", "spa_tripod"],
		"entrance": ["spa_statue_hoplite", "spa_banner"]},
	"sparta_warehouse": {"plain": ["spa_stone", "spa_spears", "spa_stone", "spa_lambda"],
		"window": ["spa_window"], "door": "spa_door",
		"floor": ["spa_floor_earth", "spa_floor_flags_b"], "mosaic": ["spa_floor_flags", "spa_floor_earth"],
		"roof": ["spa_roof_flat", "spa_roof_flat_b"], "column": "spa_column_doric",
		"caps": ["spa_cap_block", "spa_cap_block", "spa_cap_block"], "antenna": "spa_mast_spear",
		"dome": "spa_tripod_great", "horns": "spa_crown_helmet",
		"decor": ["spa_spear_rack", "spa_training_post", "spa_shield_stack", "spa_spear_rack", "spa_brazier"],
		"entrance": ["spa_banner", "spa_brazier"]},
	"sparta_temple": {"plain": ["spa_stone", "spa_lambda", "spa_inscription", "spa_stone"],
		"window": ["spa_window"], "door": "spa_door",
		"floor": ["spa_floor_flags", "spa_floor_flags_b"], "mosaic": ["spa_mosaic_meander", "spa_mosaic_lambda"],
		"roof": ["spa_roof_bronze", "spa_roof_bronze_b"], "column": "spa_column_doric",
		"caps": ["spa_cap_block", "spa_tripod_great", "spa_cap_block"], "antenna": "spa_mast_spear",
		"dome": "spa_tripod_great", "horns": "spa_crown_helmet",
		"decor": ["spa_tripod", "spa_brazier", "spa_statue_hoplite", "spa_tripod", "spa_brazier"],
		"entrance": ["spa_brazier", "spa_statue_hoplite"]},
	"athens_palace": {"plain": ["ath_stone", "ath_procession", "ath_owl", "ath_meander", "ath_triglyphs", "ath_decree"],
		"window": ["ath_window"], "door": "ath_door",
		"floor": ["ath_floor_marble", "ath_floor_marble_b"], "mosaic": ["ath_mosaic_owl", "ath_mosaic_rosette"],
		"roof": ["ath_roof_attic", "ath_roof_attic_b"], "column": "ath_column_doric",
		"caps": ["ath_cap_acroterion", "ath_cap_acroterion", "ath_cap_acroterion"], "antenna": "ath_mast_promachos",
		"dome": "ath_owl_statue", "horns": "ath_crown_pediment",
		"decor": ["ath_owl_statue", "ath_herm", "ath_olive_tree", "ath_amphora", "ath_stele", "ath_olive_tree"],
		"entrance": ["ath_herm", "ath_olive_tree"]},
	"athens_warehouse": {"plain": ["ath_stone", "ath_meander", "ath_stone", "ath_decree"],
		"window": ["ath_window"], "door": "ath_door",
		"floor": ["ath_floor_stone", "ath_floor_marble_b"], "mosaic": ["ath_floor_marble", "ath_floor_stone"],
		"roof": ["ath_roof_attic", "ath_roof_attic_b"], "column": "ath_column_doric",
		"caps": ["ath_cap_block", "ath_cap_block", "ath_cap_block"], "antenna": "ath_mast_promachos",
		"dome": "ath_owl_statue", "horns": "ath_crown_pediment",
		"decor": ["ath_amphora", "ath_stele", "ath_masks", "ath_amphora", "ath_brazier"],
		"entrance": ["ath_herm", "ath_brazier"]},
	"athens_temple": {"plain": ["ath_triglyphs", "ath_procession", "ath_owl", "ath_triglyphs"],
		"window": ["ath_window"], "door": "ath_door",
		"floor": ["ath_floor_marble", "ath_floor_marble_b"], "mosaic": ["ath_mosaic_rosette", "ath_mosaic_owl"],
		"roof": ["ath_roof_marble", "ath_roof_marble_b"], "column": "ath_column_doric",
		"caps": ["ath_cap_acroterion", "ath_cap_acroterion", "ath_cap_acroterion"], "antenna": "ath_mast_promachos",
		"dome": "ath_owl_statue", "horns": "ath_crown_pediment",
		"decor": ["ath_owl_statue", "ath_brazier", "ath_stele", "ath_olive_tree", "ath_masks"],
		"entrance": ["ath_brazier", "ath_owl_statue"]},
	"mycenae_palace": {"plain": ["myc_stone", "myc_spirals", "myc_lions", "myc_rosettes", "myc_chariot", "myc_gold"],
		"window": ["myc_window"], "door": "myc_door",
		"floor": ["myc_floor_painted", "myc_floor_painted_b"], "mosaic": ["myc_mosaic_octopus", "myc_floor_painted"],
		"roof": ["myc_roof_flat", "myc_roof_flat_b"], "column": "myc_column_taper",
		"caps": ["myc_cap_block", "myc_cap_block", "myc_cap_block"], "antenna": "myc_mast_banner",
		"dome": "myc_dome_tholos", "horns": "myc_crown_lions",
		"decor": ["myc_gold_mask", "myc_boar_helmet", "myc_wheel", "myc_jars", "myc_brazier", "myc_gold_mask"],
		"entrance": ["myc_crown_lions", "myc_brazier"]},
	"mycenae_warehouse": {"plain": ["myc_stone", "myc_gold", "myc_stone", "myc_spirals"],
		"window": ["myc_window"], "door": "myc_door",
		"floor": ["myc_floor_earth", "myc_floor_painted_b"], "mosaic": ["myc_floor_painted", "myc_floor_earth"],
		"roof": ["myc_roof_flat", "myc_roof_flat_b"], "column": "myc_column_taper",
		"caps": ["myc_cap_block", "myc_cap_block", "myc_cap_block"], "antenna": "myc_mast_banner",
		"dome": "myc_dome_tholos", "horns": "myc_crown_lions",
		"decor": ["myc_ingots", "myc_anvil", "myc_jars", "myc_wheel", "myc_ingots"],
		"entrance": ["myc_brazier", "myc_jars"]},
	"mycenae_temple": {"plain": ["myc_stone", "myc_rosettes", "myc_lions", "myc_spirals"],
		"window": ["myc_window"], "door": "myc_door",
		"floor": ["myc_floor_painted", "myc_floor_painted_b"], "mosaic": ["myc_mosaic_octopus", "myc_floor_painted"],
		"roof": ["myc_roof_flat", "myc_roof_flat_b"], "column": "myc_column_taper",
		"caps": ["myc_cap_block", "myc_cap_block", "myc_cap_block"], "antenna": "myc_mast_banner",
		"dome": "myc_dome_tholos", "horns": "myc_crown_lions",
		"decor": ["myc_gold_mask", "myc_brazier", "myc_boar_helmet", "myc_jars", "myc_brazier"],
		"entrance": ["myc_brazier", "myc_gold_mask"]},
	"ionia_palace": {"plain": ["ion_eggdart", "ion_palmettes", "ion_stars", "ion_flows", "ion_pythagoras", "ion_garden"],
		"window": ["ion_window"], "door": "ion_door",
		"floor": ["ion_floor_marble", "ion_floor_marble_b"], "mosaic": ["ion_mosaic_sun", "ion_mosaic_checker"],
		"roof": ["ion_roof_glazed", "ion_roof_glazed_b"], "column": "ion_column_ionic",
		"caps": ["ion_cap_block", "ion_cap_block", "ion_cap_block"], "antenna": "ion_mast_dish",
		"dome": "ion_armillary", "horns": "ion_crown_armillary",
		"decor": ["ion_armillary", "ion_lyre", "ion_philosopher", "ion_planter", "ion_gnomon", "ion_planter"],
		"entrance": ["ion_planter", "ion_philosopher"]},
	"ionia_warehouse": {"plain": ["ion_stone", "ion_eggdart", "ion_stone", "ion_pythagoras"],
		"window": ["ion_window"], "door": "ion_door",
		"floor": ["ion_floor_checker", "ion_floor_marble_b"], "mosaic": ["ion_floor_marble", "ion_floor_checker"],
		"roof": ["ion_roof_glazed", "ion_roof_glazed_b"], "column": "ion_column_ionic",
		"caps": ["ion_cap_block", "ion_cap_block", "ion_cap_block"], "antenna": "ion_mast_dish",
		"dome": "ion_armillary", "horns": "ion_crown_armillary",
		"decor": ["ion_gnomon", "ion_armillary", "ion_planter", "ion_lyre", "ion_brazier"],
		"entrance": ["ion_brazier", "ion_planter"]},
	"ionia_temple": {"plain": ["ion_palmettes", "ion_stars", "ion_flows", "ion_garden"],
		"window": ["ion_window"], "door": "ion_door",
		"floor": ["ion_floor_marble", "ion_floor_marble_b"], "mosaic": ["ion_mosaic_sun", "ion_mosaic_checker"],
		"roof": ["ion_roof_garden", "ion_roof_garden_b"], "column": "ion_column_ionic",
		"caps": ["ion_cap_block", "ion_cap_block", "ion_cap_block"], "antenna": "ion_mast_dish",
		"dome": "ion_armillary", "horns": "ion_crown_armillary",
		"decor": ["ion_philosopher", "ion_brazier", "ion_lyre", "ion_armillary", "ion_planter"],
		"entrance": ["ion_brazier", "ion_lyre"]},
	"cyclades_palace": {"plain": ["cyc_stone", "cyc_spirals", "cyc_longboat", "cyc_niche", "cyc_obsidian", "cyc_stone"],
		"window": ["cyc_window"], "door": "cyc_door",
		"floor": ["cyc_floor_white", "cyc_floor_schist"], "mosaic": ["cyc_mosaic_spiral", "cyc_mosaic_spiral_b"],
		"roof": ["cyc_roof_white", "cyc_roof_white_b"], "column": "cyc_column_pillar",
		"caps": ["cyc_cap_block", "cyc_cap_block", "cyc_cap_block"], "antenna": "cyc_mast_pan",
		"dome": "cyc_dome_kernos", "horns": "cyc_crown_figure",
		"decor": ["cyc_figure", "cyc_harpist", "cyc_kernos", "cyc_bowl", "cyc_pan", "cyc_figure"],
		"entrance": ["cyc_figure", "cyc_bowl"]},
	"cyclades_warehouse": {"plain": ["cyc_stone", "cyc_obsidian", "cyc_stone", "cyc_longboat"],
		"window": ["cyc_window"], "door": "cyc_door",
		"floor": ["cyc_floor_schist", "cyc_floor_schist_b"], "mosaic": ["cyc_floor_white", "cyc_floor_schist"],
		"roof": ["cyc_roof_white", "cyc_roof_white_b"], "column": "cyc_column_pillar",
		"caps": ["cyc_cap_block", "cyc_cap_block", "cyc_cap_block"], "antenna": "cyc_mast_pan",
		"dome": "cyc_dome_kernos", "horns": "cyc_crown_figure",
		"decor": ["cyc_obsidian", "cyc_bowl", "cyc_kernos", "cyc_obsidian", "cyc_pan"],
		"entrance": ["cyc_bowl", "cyc_brazier"]},
	"cyclades_temple": {"plain": ["cyc_niche", "cyc_spirals", "cyc_stone", "cyc_niche"],
		"window": ["cyc_window"], "door": "cyc_door",
		"floor": ["cyc_floor_white", "cyc_floor_schist"], "mosaic": ["cyc_mosaic_spiral", "cyc_mosaic_spiral_b"],
		"roof": ["cyc_roof_white", "cyc_roof_white_b"], "column": "cyc_column_pillar",
		"caps": ["cyc_cap_block", "cyc_cap_block", "cyc_cap_block"], "antenna": "cyc_mast_pan",
		"dome": "cyc_dome_kernos", "horns": "cyc_crown_figure",
		"decor": ["cyc_figure", "cyc_harpist", "cyc_kernos", "cyc_brazier", "cyc_figure"],
		"entrance": ["cyc_brazier", "cyc_figure"]},
}

## The culture whose buildings are being built (PlanetSurface sets it: the
## empire holding the planet's system): style("palace") is then its own
## ("sparta_palace") if it has one. "" - the styles as named.
static var culture := ""


static func style(name: String) -> Dictionary:
	if culture != "" and STYLES.has(culture + "_" + name):
		return STYLES[culture + "_" + name]
	return STYLES.get(name, STYLES["palace"])

static var _img := {}
static var _tex := {}
## After precompose: every wall, floor, roof and sprite piece as a region of
## one atlas (TextureAtlas) - a building's sprites batch into a few draw calls.
static var _atlased := {}
static var _fresh := {}             # pieces read from their PNGs (hot reload / not imported yet)


static func available() -> bool:
	return ResourceLoader.exists("res://data/sprites/%spalace_wallx_stone.png" % PREFIX)


static func names() -> Array:
	var out := []
	for f in DirAccess.get_files_at("res://data/sprites"):
		if f.begins_with(PREFIX) and f.ends_with(".png"):
			out.append(f.get_basename().trim_prefix(PREFIX))
	return out


## A tile piece as an image (at its sheet size) - never waited for: a piece
## whose picture isn't in yet comes as its procedural placeholder at the same
## size (ProcArt.image_now; is_placeholder), made again when it's in (refresh).
static func image(name: String) -> Image:
	if _img.has(name):
		return _img[name]
	var key := PREFIX + name
	var img: Image = null
	var tree := Engine.get_main_loop() as SceneTree
	var art: Node = tree.root.get_node_or_null("ProcArt") if tree else null
	if art and art.has_sprite(key) and not _fresh.has(name):
		var got: Array = art.image_now(key)
		if got[0] != null:
			img = (got[0] as Image).duplicate()
			if got[1]:
				_img_ph[name] = true
	if img == null:
		img = _from_file(name)
	if img:
		img.decompress()
		img.convert(Image.FORMAT_RGBA8)
	_img[name] = img
	return img


static var _img_ph := {}            # pieces whose image() is a placeholder (their picture not in yet)
## Walls, floors and roofs composed from placeholders: key -> [ImageTexture, its pieces].
static var _ph_tex := {}
static var _ph_busy := false


static func is_placeholder(name: String) -> bool:
	return _img_ph.has(name)


## (main thread) A piece whose picture is in now: its real image from now on.
static func upgrade(name: String) -> void:
	if _img_ph.has(name):
		_img_ph.erase(name)
		_img.erase(name)
		image(name)


## A piece as a texture to draw: the imported sprite (its placeholder until
## it's in - ProcArt.sprite: the same texture takes the picture on).
static func texture(name: String) -> Texture2D:
	if _atlased.has(name) and not _fresh.has(name):
		return _atlased[name]
	var tree := Engine.get_main_loop() as SceneTree
	var art: Node = tree.root.get_node_or_null("ProcArt") if tree else null
	if art and not _fresh.has(name) and art.has_sprite(PREFIX + name):
		return art.sprite(PREFIX + name)   # the imported sprite itself (or its placeholder)
	if not _tex.has(name):
		var img := image(name)
		if img and _fresh.has(name):
			img = img.duplicate()
			img.generate_mipmaps()   # (scaled down like the imported ones)
		_tex[name] = ImageTexture.create_from_image(img) if img else null
	return _tex[name]


## Walls, floors and roofs composed from placeholders whose pieces are all in
## now: composed again on worker threads, each texture given its new image in
## place (whatever shows it shows the real thing). Main thread; await it.
static func refresh(tree: SceneTree) -> int:
	if _ph_busy or _ph_tex.is_empty():
		return 0
	var art: Node = tree.root.get_node_or_null("ProcArt")
	if art == null:
		return 0
	var jobs := []
	for key in _ph_tex:
		var ok := true
		for n in _ph_tex[key][1]:
			if not art.is_in(PREFIX + n):
				ok = false
				break
		if ok:
			jobs.append(key)
	if jobs.is_empty():
		return 0
	_ph_busy = true
	var givens := []
	for key in jobs:
		var g := {}
		for n in _ph_tex[key][1]:
			upgrade(n)   # (the real pieces read here: workers only read them)
			g[n] = image(n)
		givens.append(g)
	var results := []
	results.resize(jobs.size())
	var work := func(i: int) -> void:
		var p := str(jobs[i]).split("|")
		results[i] = _compose_wall(p[1], p[2], p[3], givens[i]) if p[0] == "wall" else _compose_diamond(p[1], givens[i])
	var group := WorkerThreadPool.add_group_task(work, jobs.size(), maxi(1, OS.get_processor_count() - 2), false, "Minoan tiles: the real pictures")
	while not WorkerThreadPool.is_group_task_completed(group):
		await tree.process_frame
	WorkerThreadPool.wait_for_group_task_completion(group)
	for i in jobs.size():
		var entry: Array = _ph_tex.get(jobs[i], [])
		_ph_tex.erase(jobs[i])
		if not entry.is_empty() and results[i] != null:
			(entry[0] as ImageTexture).set_image(results[i])
	_ph_busy = false
	return jobs.size()


## Composing in the frame (headless runs - tests, tools - want them at once).
static func _composing_now() -> bool:
	return DisplayServer.get_name() == "headless"


## Walls, floors and roofs to compose on a worker: [key, texture, pieces, their images, from placeholders?].
static var _cq: Array = []
static var _c_task := -1
static var _c_jobs: Array = []
static var _c_out: Array = []


static func _queue_compose(key: String, tex: ImageTexture, pieces: Array) -> void:
	var given := {}
	var ph := false
	for n in pieces:
		given[n] = image(n)   # (read here, on the main thread: the worker only reads these)
		ph = ph or _img_ph.has(n)
	_cq.append([key, tex, pieces, given, ph])


## (every frame: ProcArt) The queued compositions run on a worker, a batch at a
## time; each finished one given to its texture in place.
static func pump() -> void:
	if _c_task >= 0:
		if not WorkerThreadPool.is_group_task_completed(_c_task):
			return
		WorkerThreadPool.wait_for_group_task_completion(_c_task)
		_c_task = -1
		for i in _c_jobs.size():
			var j: Array = _c_jobs[i]
			if _c_out[i] != null:
				(j[1] as ImageTexture).set_image(_c_out[i])
			if j[4]:
				_ph_tex[j[0]] = [j[1], j[2]]   # (from placeholders: again when they're in - refresh)
		_c_jobs = []
		_c_out = []
	if _cq.is_empty():
		return
	_c_jobs = _cq.slice(0, 16)
	_cq = _cq.slice(16)
	_c_out = []
	_c_out.resize(_c_jobs.size())
	var work := func(i: int) -> void:
		var j: Array = _c_jobs[i]
		var p := str(j[0]).split("|")
		_c_out[i] = _compose_wall(p[1], p[2], p[3], j[3]) if p[0] == "wall" else _compose_diamond(p[1], j[3])
	_c_task = WorkerThreadPool.add_group_task(work, _c_jobs.size(), maxi(1, OS.get_processor_count() - 2), false, "Minoan tiles")


## A piece's two colours (sizes.json: ProcArt's placeholder colours).
static func _colours(piece: String) -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	var art: Node = tree.root.get_node_or_null("ProcArt") if tree else null
	var m: Array = art._meta.get(PREFIX + piece, []) if art else []
	var main := Color.html(str(m[2])) if m.size() > 3 else Color(0.78, 0.72, 0.62)
	var shade := Color.html(str(m[3])) if m.size() > 3 else main.darkened(0.3)
	return [main, shade]


## A wall's stub until it's composed: its face (the right slope, a full
## storey) in its piece's colour, a darker course along its top - a few fills.
static func _wall_stub(orient: String, kind: String, piece: String) -> Image:
	var W := 64 * RES
	var H := (SurfaceTiles.WALL_H + 32) * RES
	var face_h := SurfaceTiles.WALL_H * RES
	var c := _colours(piece)
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for x in range(0, W, 2):
		var top := int((64.0 - x * 0.5) * RES / 2.0 if orient == "y" else x * 0.5)
		img.fill_rect(Rect2i(x, top, 2, face_h), c[0])
		img.fill_rect(Rect2i(x, top, 2, 6 * RES), c[1])
	if kind == "door":
		var x0 := int(W * SurfaceTiles.DOOR.x)
		for x in range(x0, int(W * SurfaceTiles.DOOR.y), 2):
			var top := int((64.0 - x * 0.5) * RES / 2.0 if orient == "y" else x * 0.5)
			img.fill_rect(Rect2i(x, top + int(face_h * 0.36), 2, face_h - int(face_h * 0.36)), Color(0, 0, 0, 0))
	return img


## A floor's or roof's stub: the tile's diamond in its piece's colour.
static func _diamond_stub(piece: String) -> Image:
	var TW := SurfaceTiles.TILE.x
	var TH := SurfaceTiles.TILE.y
	var c := _colours(piece)
	var img := Image.create(TW, TH, false, Image.FORMAT_RGBA8)
	for y in TH:
		var hw := int(TW * 0.5 * (1.0 - absf(y + 0.5 - TH * 0.5) / (TH * 0.5)))
		img.fill_rect(Rect2i(TW / 2 - hw, y, hw * 2, 1), c[0] if y < TH / 2 else c[0].darkened(0.08))
	return img


## A composed texture made from placeholder pieces: remembered to be redone (refresh).
static func _note_ph(key: String, tex: ImageTexture, pieces: Array) -> void:
	for n in pieces:
		if _img_ph.has(n):
			_ph_tex[key] = [tex, pieces]
			return


static func forget() -> void:
	_img_ph.clear()   # (_ph_tex kept: what was made from placeholders is still redone - refresh)
	_img.clear()
	_tex.clear()
	_atlased.clear()


## A piece straight from its PNG (one not imported yet - added while the game
## runs - or changed since: hot reload).
static func _from_file(name: String) -> Image:
	var path := ProjectSettings.globalize_path("res://data/sprites/%s%s.png" % [PREFIX, name])
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	return img


# --- Hot reload ------------------------------------------------------------------------------
# Every building sprite made from these pieces is tagged (meta SKIN) with how it
# was made - so after the pictures change (tile PNGs re-cut) or the styles do
# (STYLES extended), reskin() gives each one its texture again.

const SKIN := "minoan_skin"


static func tag(n: Node, how: Array) -> Node:
	n.set_meta(SKIN, how)
	return n


## Pieces whose PNGs changed (data/sprites/tile_*.png paths or names): read
## from the files from now on; every composed wall / floor / roof is redone.
static func hot_reload(changed: Array) -> void:
	for p in changed:
		var name := str(p).get_file().get_basename().trim_prefix(PREFIX)
		_fresh[name] = true
		_img.erase(name)
	_tex.clear()
	_atlased.clear()   # (redone one by one, unpacked, from now on)


## Every tagged sprite under `root` gets its texture from the current pieces
## and styles; floor tiles (TileSetAtlasSources) too, given as {source: [kind, variant, style]}.
static func reskin(root: Node, floor_sources := {}) -> int:
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Sprite2D and node.has_meta(SKIN):
			_reskin_sprite(node, node.get_meta(SKIN))
			n += 1
	for src in floor_sources:
		var how: Array = floor_sources[src]
		TextureAtlas.set_source_texture(src, floor_tile(how[0], how[1], how[2]))
		n += 1
	return n


static func _reskin_sprite(s: Sprite2D, how: Array) -> void:
	match how[0]:
		"wall":   # [orient, kind, variant, style]
			s.texture = wall(how[1], how[2], how[3], how[4])
		"roof":   # [variant, style]
			s.texture = roof_tile(how[1], how[2])
		"floor":  # [kind, variant, style]
			s.texture = floor_tile(how[1], how[2], how[3])
		"piece":  # [style, role (column / antenna / dome / horns / caps / entrance), index, height]
			var v: Variant = style(how[1])[how[2]]
			_resprite(s, v[int(how[3]) % v.size()] if v is Array else v, float(how[4]))
		"piece_name":   # [name, height] (a piece by name: the teleport gates)
			_resprite(s, how[1], float(how[2]))
		"decor":  # [style, roll]
			var picks: Array = style(how[1])["decor"]
			_resprite(s, picks[int(how[2]) % picks.size()], 0.0)


## Like sprite(): the piece standing on the sprite's foot (its position).
static func _resprite(s: Sprite2D, name: String, height: float) -> void:
	var tex := texture(name)
	if tex == null:
		return
	s.texture = tex
	var k := (height / tex.get_height()) if height > 0.0 else PIECE_SCALE
	s.scale = Vector2(k, k)
	s.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height())


# --- Walls ---------------------------------------------------------------------------------
# Texture assembly works on raw RGBA bytes (fast, and safe on worker threads:
# the source images are only read). precompose() builds every variant on
# worker threads while the loading screen shows.

## Opaque rows of each column of an RGBA8 image: PackedInt32Array [top0, bot0, top1, bot1, ...].
static func _columns(data: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(w * 2)
	out.fill(-1)
	for y in h:
		var row := y * w * 4
		for x in w:
			if data[row + x * 4 + 3] > 127:
				if out[x * 2] < 0:
					out[x * 2] = y
				out[x * 2 + 1] = y
	return out


## The wall design for a kind / variant ("palace_bull", "wh_slate", ...).
static func _wall_design(kind: String, variant: int, st := "palace") -> String:
	var d := style(st)
	match kind:
		"door": return d["door"]
		"window": return d["window"][variant % d["window"].size()]
		_: return d["plain"][variant % d["plain"].size()]


## A wall face in SurfaceTiles' layout (64 x WALL_H + 32, here at RES x).
## orient "x" runs down-right, "y" up-right.
static func wall(orient: String, kind: String, variant: int, st := "palace") -> Texture2D:
	var design := _wall_design(kind, variant, st)
	var key := "wall|%s|%s|%s" % [orient, kind, design]
	if _atlased.has(key):
		return _atlased[key]
	if not _tex.has(key):
		var pieces := [_wall_piece(design, orient), _cap_piece(design, orient)]
		if _composing_now():
			_tex[key] = ImageTexture.create_from_image(_compose_wall(orient, kind, design))
			_note_ph(key, _tex[key], pieces)
		else:   # (a stub shape now; composed on a worker, in place - never in the frame)
			_tex[key] = ImageTexture.create_from_image(_wall_stub(orient, kind, pieces[0]))
			_queue_compose(key, _tex[key], pieces)
	return _tex[key]


## A wall design's piece for an orientation: "wh_slate" -> "wh_wallx_slate".
static func _wall_piece(design: String, orient: String) -> String:
	var sheet := design.get_slice("_", 0)
	return "%s_wall%s_%s" % [sheet, orient, design.trim_prefix(sheet + "_")]


## The plain stone wall of a design's sheet (tops walls up to a storey).
static func _cap_piece(design: String, orient: String) -> String:
	var sheet: String = CAP_FROM.get(design.get_slice("_", 0), design.get_slice("_", 0))
	return "%s_wall%s_%s" % [sheet, orient, CAP_WALL.get(sheet, "stone")]


## The sheet's wall piece scaled uniformly to one tile edge, set on the
## ground line; above it, the stone wall's upper courses (same scale) up to
## a full storey. Doors: the opening is cut out (the sliding door fills it).
static func _compose_wall(orient: String, kind: String, design: String, given := {}) -> Image:
	var src: Image = given.get(_wall_piece(design, orient)) if given.has(_wall_piece(design, orient)) else image(_wall_piece(design, orient))
	var cap: Image = given.get(_cap_piece(design, orient)) if given.has(_cap_piece(design, orient)) else image(_cap_piece(design, orient))
	var sd := src.get_data()
	var cd := cap.get_data()
	var sw := src.get_width()
	var shh := src.get_height()
	var cw := cap.get_width()
	var chh := cap.get_height()
	var sc := _columns(sd, sw, shh)
	var cc := _columns(cd, cw, chh)
	var W := 64 * RES
	var H := (SurfaceTiles.WALL_H + 32) * RES
	var face_h := float(SurfaceTiles.WALL_H * RES)
	var k := float(W) / sw          # uniform scale: one sheet wall = one tile edge
	var kc := float(W) / cw
	var od := PackedByteArray()
	od.resize(W * H * 4)
	var door := kind == "door"
	for x in W:
		var u := (x + 0.5) / W
		var sx := clampi(int(u * sw), 0, sw - 1)
		var cx := clampi(int(u * cw), 0, cw - 1)
		var top := (64.0 - x * 0.5) * RES / 2.0 if orient == "y" else x * 0.5
		var bottom := top + face_h
		var ct := sc[sx * 2]
		var cb := sc[sx * 2 + 1]
		if ct < 0:
			continue
		ct += CAP_CROP   # the piece's own top cap goes under the course above
		var piece_h := minf((cb - ct + 1) * k, face_h)
		var piece_top := bottom - piece_h
		var ctop := cc[cx * 2]
		var in_door := door and u > SurfaceTiles.DOOR.x and u < SurfaceTiles.DOOR.y
		for y in range(int(top), mini(int(bottom) + 1, H)):
			if in_door and (y - top) / face_h > 0.36:
				continue   # the doorway: the sliding door fills it
			var si: int
			var data: PackedByteArray
			if y >= piece_top:
				si = (clampi(ct + int((y - piece_top) / k), 0, shh - 1) * sw + sx) * 4
				data = sd
			elif ctop >= 0:
				si = (clampi(ctop + int((y - top) / kc), 0, chh - 1) * cw + cx) * 4
				data = cd
			else:
				continue
			if data[si + 3] == 0:
				continue
			var oi := (y * W + x) * 4
			od[oi] = data[si]
			od[oi + 1] = data[si + 1]
			od[oi + 2] = data[si + 2]
			od[oi + 3] = data[si + 3]
	return Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, od)


# --- Floors and roofs ----------------------------------------------------------------------

## The top face of a block piece, warped onto a TILE-sized diamond.
static func diamond(piece: String) -> Texture2D:
	var key := "diamond|" + piece
	if _atlased.has(key):
		return _atlased[key]
	if not _tex.has(key):
		if _composing_now():
			_tex[key] = ImageTexture.create_from_image(_compose_diamond(piece))
			_note_ph(key, _tex[key], [piece])
		else:   # (a stub diamond now; composed on a worker, in place)
			_tex[key] = ImageTexture.create_from_image(_diamond_stub(piece))
			_queue_compose(key, _tex[key], [piece])
	return _tex[key]


static func _compose_diamond(piece: String, given := {}) -> Image:
	var src: Image = given.get(piece) if given.has(piece) else image(piece)
	var sd := src.get_data()
	var w := src.get_width()
	var h := src.get_height()
	# Top face corners: the topmost, leftmost and rightmost opaque points; the
	# fourth corner completes the parallelogram.
	var T := Vector2(-1, h)
	var L := Vector2(w, 0)
	var R := Vector2(-1, 0)
	for y in h:
		for x in w:
			if sd[(y * w + x) * 4 + 3] > 127:
				if y < T.y:
					T = Vector2(x, y)
				if x < L.x:
					L = Vector2(x, y)
				if x > R.x:
					R = Vector2(x, y)
	var TW := SurfaceTiles.TILE.x
	var TH := SurfaceTiles.TILE.y
	var od := PackedByteArray()
	od.resize(TW * TH * 4)
	for y in TH:
		for x in TW:
			var uu := (x + 0.5 - TW / 2.0) / TW + (y + 0.5) / TH
			var vv := (y + 0.5) / TH - (x + 0.5 - TW / 2.0) / TW
			if uu < 0.0 or vv < 0.0 or uu > 1.0 or vv > 1.0:
				continue
			# Inset a little: the face's outer edge is the block's bevel.
			var p := T + (R - T) * lerpf(0.04, 0.96, uu) + (L - T) * lerpf(0.04, 0.96, vv)
			var si := (clampi(int(p.y), 0, h - 1) * w + clampi(int(p.x), 0, w - 1)) * 4
			if sd[si + 3] == 0:
				continue
			var oi := (y * TW + x) * 4
			od[oi] = sd[si]
			od[oi + 1] = sd[si + 1]
			od[oi + 2] = sd[si + 2]
			od[oi + 3] = 255
	return Image.create_from_data(TW, TH, false, Image.FORMAT_RGBA8, od)


static func floor_tile(kind: String, variant: int, st := "palace") -> Texture2D:
	var list: Array = style(st)["mosaic" if kind == "mosaic" else "floor"]
	return diamond(list[variant % list.size()])


static func roof_tile(variant: int, st := "palace") -> Texture2D:
	var list: Array = style(st)["roof"]
	return diamond(list[variant % list.size()])


## Builds every wall / floor / roof texture on worker threads (the loading
## screen keeps animating). Call from the main thread; await it.
static func precompose(tree: SceneTree) -> void:
	if not available():
		return
	var jobs := []
	var seen := {}
	var sources := {}
	for st in STYLES:
		for orient in ["x", "y"]:
			for kind in ["plain", "window", "door"]:
				for v in 20:
					var design := _wall_design(kind, v, st)
					sources[_wall_piece(design, orient)] = true
					sources[_cap_piece(design, orient)] = true
					var key := "wall|%s|%s|%s" % [orient, kind, design]
					if not seen.has(key) and not _tex.has(key):
						seen[key] = true
						jobs.append([key, "wall", orient, kind, design])
		for k in ["floor", "mosaic", "roof"]:
			for piece in STYLES[st][k]:
				sources[piece] = true
				if not seen.has("diamond|" + piece) and not _tex.has("diamond|" + piece):
					seen["diamond|" + piece] = true
					jobs.append(["diamond|" + piece, "diamond", piece])
	# Source images are fetched here (main thread); workers only read them.
	var t := Time.get_ticks_usec()
	for n in sources:
		image(n)
		if Time.get_ticks_usec() - t > 8000:
			await tree.process_frame
			t = Time.get_ticks_usec()
	var results := []
	results.resize(jobs.size())
	var lock := Mutex.new()
	var work := func(i: int) -> void:
		var j: Array = jobs[i]
		var img: Image = _compose_wall(j[2], j[3], j[4]) if j[1] == "wall" else _compose_diamond(j[2])
		lock.lock()
		results[i] = img
		lock.unlock()
	var group := WorkerThreadPool.add_group_task(work, jobs.size(), maxi(1, OS.get_processor_count() - 2), false, "Minoan tiles")
	while not WorkerThreadPool.is_group_task_completed(group):
		await tree.process_frame
	WorkerThreadPool.wait_for_group_task_completion(group)
	# Upload to the GPU a few per frame (keeps the loading screen smooth).
	# Sprite pieces (columns, roof crowns, decor) as ready textures too.
	var t3 := Time.get_ticks_usec()
	var pieces := {}
	for st in STYLES:
		var d: Dictionary = STYLES[st]
		for n in d["decor"] + d["entrance"] + d["caps"] + [d["column"], d["antenna"], d["dome"], d["horns"]]:
			pieces[n] = texture(n)
			if Time.get_ticks_usec() - t3 > 8000:
				await tree.process_frame
				t3 = Time.get_ticks_usec()
	for extra in ATLAS_EXTRA:
		if texture(extra) != null:
			pieces[extra] = texture(extra)
	# Everything in one atlas: the composed walls / floors / roofs and the
	# sprite pieces (their images: the imported ones read back once).
	var keys := []
	var imgs := []
	for i in jobs.size():
		if results[i] != null:
			keys.append(jobs[i][0])
			imgs.append(results[i])
	for n in pieces:
		if pieces[n] != null and not _fresh.has(n):
			var im: Image = image(n)
			if im == null:
				im = (pieces[n] as Texture2D).get_image()
			if im != null and im.get_size() == Vector2i((pieces[n] as Texture2D).get_size()):
				keys.append(n)
				imgs.append(im)
	await tree.process_frame
	var ats := TextureAtlas.textures(imgs)
	for i in keys.size():
		if ats[i] != null:
			_atlased[keys[i]] = ats[i]
		elif i < jobs.size() and results[i] != null:
			_tex[keys[i]] = ImageTexture.create_from_image(imgs[i])


# --- Columns and decor --------------------------------------------------------------------

## A sprite of a piece, standing on `foot` (its bottom centre), scaled to `height`
## pixels tall (or PIECE_SCALE x its sheet size).
static func sprite(name: String, foot: Vector2, height := 0.0) -> Sprite2D:
	var tex := texture(name)
	var s := Sprite2D.new()
	if tex == null:
		return s
	s.texture = tex
	s.centered = false
	var k := (height / tex.get_height()) if height > 0.0 else PIECE_SCALE
	s.scale = Vector2(k, k)
	s.position = foot
	s.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height())
	return s
