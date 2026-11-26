class_name TracedShips
## The ship classes drawn on the player's reference sheets: the twelve
## independents here plus the empires' own (EmpireShips). Their sprites are
## the PNGs cut out of the sheets (data/sprites/ship_traced_<key>.png, made by
## tools/extract_sprites.py); this is their data: name, role (Shipyard
## class), price and palette.


## id -> {name, role (Shipyard class), len, width, price, palette}
const SHIPS := {
	"ember": {"name": "Ember-class Fighter", "role": "fighter", "len": 370.0, "width": 250.0, "price": 4200,
		"palette": {"main": Color(0.95, 0.5, 0.12), "accent": Color(1.0, 0.75, 0.12), "dark": Color(0.25, 0.24, 0.24), "glow": Color(1.0, 0.62, 0.18), "glass": Color(0.08, 0.06, 0.05)}},
	"skylance": {"name": "Skylance-class Interceptor", "role": "interceptor", "len": 360.0, "width": 290.0, "price": 4800,
		"palette": {"main": Color(0.9, 0.91, 0.93), "accent": Color(0.15, 0.4, 0.9), "dark": Color(0.28, 0.29, 0.32), "glow": Color(0.35, 0.75, 1.0), "glass": Color(0.05, 0.1, 0.2)}},
	"bulwark": {"name": "Bulwark-class Gunship", "role": "gunship", "len": 210.0, "width": 250.0, "price": 6500,
		"palette": {"main": Color(0.52, 0.56, 0.3), "accent": Color(0.95, 0.72, 0.2), "dark": Color(0.25, 0.26, 0.22), "glow": Color(1.0, 0.65, 0.2), "glass": Color(0.1, 0.25, 0.35)}},
	"crescent": {"name": "Crescent-class Fighter", "role": "fighter", "len": 340.0, "width": 270.0, "price": 5200,
		"palette": {"main": Color(0.8, 0.14, 0.12), "accent": Color(0.85, 0.85, 0.87), "dark": Color(0.24, 0.24, 0.27), "glow": Color(0.35, 0.75, 1.0), "glass": Color(0.05, 0.08, 0.15)}},
	"violet_dart": {"name": "Violet Dart-class Interceptor", "role": "interceptor", "len": 370.0, "width": 250.0, "price": 4500,
		"palette": {"main": Color(0.5, 0.3, 0.7), "accent": Color(0.75, 0.55, 0.9), "dark": Color(0.2, 0.17, 0.26), "glow": Color(1.0, 0.3, 0.9), "glass": Color(0.08, 0.03, 0.1)}},
	"halo": {"name": "Halo-class Explorer", "role": "explorer", "len": 310.0, "width": 320.0, "price": 5600,
		"palette": {"main": Color(0.88, 0.88, 0.86), "accent": Color(0.8, 0.12, 0.1), "dark": Color(0.27, 0.28, 0.31), "glow": Color(0.35, 0.8, 1.0), "glass": Color(0.05, 0.1, 0.18)}},
	"hornet": {"name": "Hornet-class Hauler", "role": "freighter", "len": 345.0, "width": 240.0, "price": 6200,
		"palette": {"main": Color(0.95, 0.72, 0.12), "accent": Color(0.12, 0.12, 0.12), "dark": Color(0.22, 0.22, 0.22), "glow": Color(1.0, 0.65, 0.2), "glass": Color(0.05, 0.05, 0.06)}},
	"tidewing": {"name": "Tidewing-class Fighter", "role": "fighter", "len": 355.0, "width": 270.0, "price": 4900,
		"palette": {"main": Color(0.22, 0.65, 0.62), "accent": Color(0.5, 0.88, 0.85), "dark": Color(0.18, 0.28, 0.3), "glow": Color(0.35, 0.95, 1.0), "glass": Color(0.04, 0.1, 0.12)}},
	"nightjar": {"name": "Nightjar-class Stealth Fighter", "role": "fighter", "len": 370.0, "width": 270.0, "price": 5800,
		"palette": {"main": Color(0.3, 0.31, 0.33), "accent": Color(0.95, 0.55, 0.15), "dark": Color(0.16, 0.16, 0.18), "glow": Color(1.0, 0.6, 0.2), "glass": Color(0.05, 0.05, 0.06)}},
	"atlas": {"name": "Atlas-class Freighter", "role": "freighter", "len": 350.0, "width": 240.0, "price": 6800,
		"palette": {"main": Color(0.2, 0.42, 0.78), "accent": Color(0.85, 0.85, 0.82), "dark": Color(0.18, 0.19, 0.23), "glow": Color(1.0, 0.65, 0.2), "glass": Color(0.05, 0.06, 0.1)}},
	"aether": {"name": "Aether-class Courier", "role": "courier", "len": 350.0, "width": 270.0, "price": 5400,
		"palette": {"main": Color(0.82, 0.82, 0.86), "accent": Color(0.6, 0.25, 0.85), "dark": Color(0.25, 0.25, 0.3), "glow": Color(0.8, 0.35, 1.0), "glass": Color(0.08, 0.04, 0.12)}},
	# The Independents' civilian haulers (placeholders: the Atlas and the
	# Hornet recoloured steel and emerald - tools/recolor_sprite.py).
	"drifter": {"name": "Drifter-class Freighter", "role": "freighter", "len": 350.0, "width": 240.0, "price": 6400,
		"palette": {"main": Color(0.62, 0.66, 0.7), "accent": Color(0.3, 0.85, 0.5), "dark": Color(0.18, 0.2, 0.22), "glow": Color(0.4, 1.0, 0.6), "glass": Color(0.05, 0.08, 0.06)}},
	"prospector": {"name": "Prospector-class Hauler", "role": "freighter", "len": 345.0, "width": 240.0, "price": 5900, "civil": "miner",
		"palette": {"main": Color(0.62, 0.66, 0.7), "accent": Color(0.3, 0.85, 0.5), "dark": Color(0.18, 0.2, 0.22), "glow": Color(0.4, 1.0, 0.6), "glass": Color(0.05, 0.08, 0.06)}},
	"bastion": {"name": "Bastion-class Frigate", "role": "frigate", "len": 350.0, "width": 250.0, "price": 9500,
		"palette": {"main": Color(0.88, 0.86, 0.8), "accent": Color(0.78, 0.15, 0.12), "dark": Color(0.22, 0.2, 0.2), "glow": Color(1.0, 0.6, 0.2), "glass": Color(0.08, 0.05, 0.03)}},
}


static var _every := {}


## Independent designs plus the empires' own (EmpireShips).
static func all() -> Dictionary:
	if _every.is_empty():
		_every = SHIPS.duplicate()
		_every.merge(EmpireShips.MINOA)
		_every.merge(EmpireShips.PIRATES)
		_every.merge(EmpireShips.ATHENS)
		_every.merge(EmpireShips.sparta())
		_every.merge(EmpireShips.IONIA)
		_every.merge(EmpireShips.CYCLADES)
	return _every


static func ids() -> Array:
	return all().keys().map(func(k): return "traced_" + k)


static func def(id: String) -> Dictionary:
	return all().get(id.trim_prefix("traced_"), {})


## EnemyTypes-format stats for a traced class.
static func type_of(id: String) -> Dictionary:
	var d := def(id)
	if d.is_empty():
		return {}
	var base: Array = {"fighter": [60.0, 40.0, 300.0], "interceptor": [45.0, 30.0, 330.0], "gunship": [130.0, 60.0, 190.0],
		"explorer": [80.0, 80.0, 240.0], "freighter": [170.0, 50.0, 150.0], "courier": [55.0, 45.0, 320.0], "frigate": [200.0, 100.0, 140.0]}.get(d["role"], [60.0, 40.0, 280.0])
	var emp: String = d.get("empire", "")
	return {"name": d["name"], "empire_style": emp, "class": d["role"], "traced": true, "price": d["price"],
		"desc": ("An independent design: %s." % d["name"]) if emp == "" else ("%s of the %s." % [d["name"], Galaxy.EMPIRES[emp]["name"]]), "length": 150.0 if d["role"] in ["fighter", "interceptor", "courier"] else 190.0,
		"hull": base[0], "shields": base[1], "speed": base[2], "fire_interval": 1.0, "damage": 8.0,
		"bullet_speed": 700.0, "shots": 2 if d["role"] in ["gunship", "frigate"] else 1, "aggro": 600.0, "distance": 360.0,
		"color": d["palette"]["glow"]}
