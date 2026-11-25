class_name AssetCatalog
extends RefCounted
## Every asset of the game, sorted by who it belongs to - the Library's asset
## browser (AssetBrowser) lists it. owners() returns, in order:
##   [{id, name, color, categories: [{name, entries: [entry...]}]}]
## and an entry is
##   {title, sub, key (unique), tex (a res:// path or a ProcArt key; "" = none),
##    swatch (a Color, for procedural assets drawn as a disc), info (text),
##    room (the Library's live room showing it), spot (where in that room)}.
## Empires (their ships, stations, people, buildings, effects), the
## Independents, the Sea Peoples, you, the monsters, the wildlife, then the
## galaxy itself (planets, suns, nebulae, asteroids, jump gates, terrain) and
## the interface. Built once (cached); the textures load when shown.

static var _cache: Array = []


static func owners() -> Array:
	if _cache.is_empty():
		_cache = _build()
	return _cache


## Forget the catalog (after new art came in).
static func reset() -> void:
	_cache = []


static func _owner(id: String, name: String, color: Color) -> Dictionary:
	return {"id": id, "name": name, "color": color, "categories": []}


static func _add(o: Dictionary, category: String, e: Dictionary) -> void:
	for c in o["categories"]:
		if c["name"] == category:
			c["entries"].append(e)
			return
	o["categories"].append({"name": category, "entries": [e]})


static func _e(title: String, key: String, tex := "", info := "", room := "", spot := "", sub := "") -> Dictionary:
	return {"title": title, "sub": sub, "key": key, "tex": tex, "swatch": Color(0, 0, 0, 0), "info": info, "room": room, "spot": spot}


## The sprite files of data/sprites starting with `prefix` (keys, sorted).
static func sprite_keys(prefix: String) -> Array:
	var out := []
	var d := DirAccess.open(ProcArt.SPRITES)
	if d == null:
		return out
	for f in d.get_files():
		f = f.trim_suffix(".import").trim_suffix(".remap")
		if f.begins_with(prefix) and f.ends_with(".png") and not out.has(f.trim_suffix(".png")):
			out.append(f.trim_suffix(".png"))
	out.sort()
	return out


## The first of these res:// paths that exists ("" if none).
static func first_file(paths: Array) -> String:
	for p in paths:
		if ResourceLoader.exists(p):
			return p
	return ""


static func _build() -> Array:
	var by := {}
	var order := ["minoa", "athens", "sparta", "mycenae", "ionia", "cyclades", "independent", "pirates", "player", "monsters", "wildlife", "galaxy", "interface"]
	for e in ["minoa", "athens", "sparta", "mycenae", "ionia", "cyclades", "independent", "pirates"]:
		by[e] = _owner(e, Galaxy.empire_name(e), Galaxy.empire_color(e))
	by["player"] = _owner("player", "You, the pilot", Color(1.0, 0.6, 0.25))
	by["monsters"] = _owner("monsters", "Monsters and bosses", Color(0.9, 0.35, 0.35))
	by["wildlife"] = _owner("wildlife", "Wildlife", Color(0.55, 0.85, 0.45))
	by["galaxy"] = _owner("galaxy", "The galaxy", Color(0.65, 0.75, 0.95))
	by["interface"] = _owner("interface", "The interface", NeonTheme.CYAN)

	# Ships: whoever flies the design (ShipDesigns.owner_of); the bosses apart.
	by["player"]["categories"].append({"name": "Ship", "entries": [_e("Your ship", "ship:player", "ship_player", "The player's ship, as fitted at the start.", "SHIPS", "player")]})
	var t := EnemyTypes.types()
	var ids: Array = t.keys()
	ids.sort()
	for id in ids:
		var d: Dictionary = t[id]
		var info := "%s\nClass: %s  ·  hull %d  ·  shields %d  ·  speed %d%s\nLength in game: %d" % [d.get("desc", ""), str(d.get("class", "?")).capitalize(),
			int(d.get("hull", 0)), int(d.get("shields", 0)), int(d.get("speed", 0)), ("  ·  %d dr" % int(d["price"])) if d.has("price") else "", int(d.get("length", 0))]
		var e := _e(str(d.get("name", id)), "ship:" + id, "type:" + id, info, "SHIPS", id, str(d.get("role", d.get("class", ""))).capitalize())
		if d.get("unique", false):
			_add(by["monsters"], "Bosses", e)
			continue
		var o := ShipDesigns.owner_of(id)
		if not by.has(o):
			o = "independent"
		_add(by[o], "Ships", e)

	# Stations: StationArt.BY_EMPIRE.
	for o in StationArt.BY_EMPIRE:
		for dsg in StationArt.BY_EMPIRE[o]:
			var info: Dictionary = StationArt.DESIGNS[dsg]
			_add(by[o], "Stations", _e(info["name"], "station:" + dsg, "station_" + dsg,
				"A %s station design (%s). Spins as in the game." % [Galaxy.EMPIRES.get(o, {}).get("short", o), dsg], "STATIONS", dsg))

	# People.
	var people := [["android_rifle", "Android rifleman", "minoa"], ["android_bow", "Android archer", "minoa"],
		["android_axe", "Android with a labrys", "minoa"], ["guard", "Palace guard", "minoa"], ["kilon", "Kilon Alios", "minoa"],
		["pirate", "Sea Peoples raider", "pirates"], ["player", "The pilot on foot", "player"]]
	for p in people:
		var path := first_file(["res://art/%s/%s_idle_s.png" % [p[0], p[0]], "res://art/%s/%s_aim_s.png" % [p[0], p[0]],
			"res://art/%s/%s_walk_s_0.png" % [p[0], p[0]], "res://art/%s/%s_portrait.png" % [p[0], p[0]]])
		_add(by[p[2]], "Characters", _e(p[1], "char:" + p[0], path, "Drawn in 8 directions (art/%s/): idle, walking, aiming." % p[0], "CHARACTERS"))
	for k in sprite_keys("npc_minoan_"):
		_add(by["minoa"], "Portraits", _e(k.trim_prefix("npc_minoan_").replace("_", " ").capitalize(), "npc:" + k, k, "A portrait for dialogue (data/sprites/%s.png)." % k, "CHARACTERS"))

	# Minoan buildings: the tile styles' pieces, the furniture.
	for k in sprite_keys("tile_palace_") + sprite_keys("tile_wh_") + sprite_keys("tile_xt_"):
		var nm: String = str(k).trim_prefix("tile_")
		_add(by["minoa"], "Buildings", _e(nm.replace("_", " ").capitalize(), "tile:" + nm, k, "A Minoan building piece (data/sprites/%s.png): walls, floors, roofs, columns, decor - the styles in MinoanTiles." % k, "BUILDINGS"))
	var fd := DirAccess.open("res://art/furniture")
	if fd:
		var files: Array = Array(fd.get_files()).map(func(f): return str(f).trim_suffix(".import").trim_suffix(".remap")).filter(func(f): return str(f).ends_with(".png"))
		var seen := {}
		files.sort()
		for f in files:
			if seen.has(f):
				continue
			seen[f] = true
			_add(by["minoa"], "Furniture", _e(f.trim_suffix(".png").replace("_", " ").capitalize(), "furn:" + f, "res://art/furniture/" + f, "Minoan furniture (art/furniture/%s)." % f, "BUILDINGS"))
	# Effects: the androids' and the rifle's (Minoan arms).
	for k in sprite_keys("fx_"):
		_add(by["minoa"], "Effects", _e(k.trim_prefix("fx_").replace("_", " ").capitalize(), "fx:" + k, k, "An effect sprite (data/sprites/%s.png), drawn glowing." % k, "EFFECTS"))

	# Monsters: the signal sites' creatures (their body sprite).
	var monsters := {}
	for k in sprite_keys("monster_"):
		monsters[k.trim_prefix("monster_").get_slice("_", 0)] = true
	for m in monsters:
		var tex := ""
		for cand in ["monster_%s_body" % m, "monster_%s_front" % m, "monster_%s_torso" % m, "monster_%s" % m]:
			if ProcArt.has_sprite(cand):
				tex = cand
				break
		_add(by["monsters"], "Creatures of myth", _e(str(m).capitalize(), "monster:" + m, tex, "A monster of the signal sites, rigged from its parts (data/sprites/monster_%s_*.png)." % m, "MONSTERS"))

	# Wildlife by planet kind.
	var kinds := {"fo": "Forest worlds", "ic": "Ice worlds", "vo": "Volcanic worlds"}
	for k in sprite_keys("creature_"):
		if not k.ends_with("_stand"):
			continue
		var id: String = str(k).trim_prefix("creature_").trim_suffix("_stand")
		_add(by["wildlife"], kinds.get(id.get_slice("_", 0), "Others"), _e(id.get_slice("_", 1).capitalize(), "creature:" + id, k,
			"Wildlife (data/sprites/creature_%s_*.png): standing, moving, acting." % id))

	# The galaxy: procedural worlds (drawn as discs), gates, skies, terrain.
	for tpl in PlanetGen.TEMPLATES:
		var e := _e(PlanetGen.TEMPLATES[tpl]["name"], "planet:" + tpl, "", "A planet template (PlanetGen): every planet of the galaxy is one of these, mixed and recoloured.", "PLANETS", "", "Planet template")
		e["swatch"] = _spec_color(PlanetGen.generate(tpl, 0))
		_add(by["galaxy"], "Planets", e)
	for tpl in StarGen.TEMPLATES:
		var e := _e(StarGen.TEMPLATES[tpl]["name"], "star:" + tpl, "", "A star template (StarGen).", "SUNS", "", "Star")
		e["swatch"] = _spec_color(StarGen.generate(tpl, 0))
		_add(by["galaxy"], "Suns", e)
	for tpl in NebulaGen.TEMPLATES:
		var e := _e(NebulaGen.TEMPLATES[tpl]["name"], "nebula:" + tpl, "", "A nebula template (NebulaGen): the systems' backdrops.", "NEBULAE", "", "Nebula")
		e["swatch"] = _spec_color(NebulaGen.generate(tpl, 0))
		_add(by["galaxy"], "Nebulae", e)
	for tpl in AsteroidGen.TEMPLATES:
		var e := _e(AsteroidGen.TEMPLATES[tpl]["name"], "asteroid:" + tpl, "", "An asteroid template (AsteroidGen).", "ASTEROIDS", "", "Asteroid")
		e["swatch"] = _spec_color(AsteroidGen.generate(tpl, 0))
		_add(by["galaxy"], "Asteroids", e)
	for k in sprite_keys("gate_"):
		_add(by["galaxy"], "Jump gates", _e(k.trim_prefix("gate_").replace("_", " ").capitalize(), "gate:" + k, k, "A jump gate piece (data/sprites/%s.png)." % k))
	for k in sprite_keys("sky_"):
		_add(by["galaxy"], "Skies", _e(k.trim_prefix("sky_").replace("_", " ").capitalize(), "sky:" + k, k, "A planet's sky layer (data/sprites/%s.png)." % k))
	var terrain := {"fo": "Terrain: forest", "ic": "Terrain: ice", "vo": "Terrain: volcanic", "gg": "Terrain: gas giant platforms"}
	for pre in terrain:
		for k in sprite_keys("tile_%s_" % pre):
			_add(by["galaxy"], terrain[pre], _e(k.trim_prefix("tile_").replace("_", " ").capitalize(), "tile:" + k, k, "A terrain tile (data/sprites/%s.png)." % k))

	by["interface"]["categories"].append({"name": "Widgets", "entries": [_e("The interface", "gui:board", "",
		"Every kind of widget on a sample board; its look (colours, panels, corners, borders, glow) is edited live in the property panel.", "GUI", "", "Look and widgets")]})
	var out := []
	for o in order:
		if not by[o]["categories"].is_empty():
			out.append(by[o])
	return out


## A procedural spec's main colour (for its swatch).
static func _spec_color(spec: Dictionary) -> Color:
	for k in ["color_light", "color", "core", "main", "tint", "color_a", "glow"]:
		if spec.get(k) is Color:
			return spec[k]
	for k in spec:
		if spec[k] is Color:
			return spec[k]
	return Color(0.6, 0.6, 0.65)


## The texture of an entry ("" -> null), loaded on demand.
static func texture(e: Dictionary) -> Texture2D:
	var t: String = e.get("tex", "")
	if t == "":
		return null
	if t.begins_with("type:"):
		return EnemyTypes.texture(t.trim_prefix("type:"))
	if t.begins_with("res://"):
		return load(t) as Texture2D if ResourceLoader.exists(t) else null
	return ProcArt.get_tex(t)


## Every entry, flattened: [[owner, category, entry]...].
static func all_entries() -> Array:
	var out := []
	for o in owners():
		for c in o["categories"]:
			for e in c["entries"]:
				out.append([o, c, e])
	return out
