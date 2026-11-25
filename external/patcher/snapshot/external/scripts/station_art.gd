class_name StationArt
## The space-station designs from the reference sheets (data/sprites/
## station_<design>.png, cut out by tools/extract_sprites.py) and which
## empire builds which. A station picks one by its id and spins it slowly.

const WHITE := Color(0.86, 0.86, 0.84)

const DESIGNS := {
	"wheel": {"name": "Orange Wheel", "main": Color(0.95, 0.5, 0.12), "accent": WHITE, "glow": Color(1.0, 0.62, 0.2)},
	"star": {"name": "Blue Star", "main": Color(0.15, 0.38, 0.8), "accent": WHITE, "glow": Color(0.35, 0.75, 1.0)},
	"forge": {"name": "Yellow Forge", "main": Color(0.95, 0.75, 0.15), "accent": Color(0.2, 0.2, 0.2), "glow": Color(1.0, 0.65, 0.2)},
	"crescents": {"name": "Red Crescents", "main": Color(0.8, 0.14, 0.12), "accent": WHITE, "glow": Color(0.35, 0.75, 1.0)},
	"violet_sun": {"name": "Violet Sun", "main": Color(0.55, 0.3, 0.75), "accent": WHITE, "glow": Color(0.85, 0.35, 1.0)},
	"halo": {"name": "Orbital Halo", "main": WHITE, "accent": Color(0.95, 0.55, 0.15), "glow": Color(1.0, 0.65, 0.2)},
	"gateway": {"name": "Gateway", "main": WHITE, "accent": Color(0.9, 0.35, 0.12), "glow": Color(1.0, 0.6, 0.2)},
	"lotus": {"name": "Lotus Gardens", "main": Color(0.3, 0.7, 0.68), "accent": Color(0.85, 0.65, 0.2), "glow": Color(0.5, 1.0, 0.8)},
	"trident": {"name": "Trident", "main": Color(0.92, 0.52, 0.12), "accent": WHITE, "glow": Color(1.0, 0.62, 0.2)},
	"solar": {"name": "Solar Array", "main": WHITE, "accent": Color(0.15, 0.3, 0.65), "glow": Color(1.0, 0.65, 0.2)},
	"vortex": {"name": "Scythe Vortex", "main": WHITE, "accent": Color(0.6, 0.25, 0.85), "glow": Color(0.85, 0.35, 1.0)},
	"ionia_lyre": {"name": "Lyre Sanctum", "main": Color(0.9, 0.86, 0.74), "accent": Color(0.16, 0.26, 0.66), "glow": Color(0.35, 0.8, 1.0)},
	"ionia_garden": {"name": "Garden Ring", "main": Color(0.9, 0.86, 0.74), "accent": Color(0.3, 0.5, 0.25), "glow": Color(0.35, 0.8, 1.0)},
	"ionia_waves": {"name": "Wave Vortex", "main": Color(0.9, 0.86, 0.74), "accent": Color(0.16, 0.26, 0.66), "glow": Color(0.35, 0.8, 1.0)},
	"ionia_laurel": {"name": "Laurel Sun", "main": Color(0.9, 0.86, 0.74), "accent": Color(0.16, 0.26, 0.66), "glow": Color(0.35, 0.8, 1.0)},
	"ionia_crescent": {"name": "Crescent Gate", "main": Color(0.9, 0.86, 0.74), "accent": Color(0.16, 0.26, 0.66), "glow": Color(0.35, 0.8, 1.0)},
	"ionia_pegasus": {"name": "Pegasus Cross", "main": Color(0.9, 0.86, 0.74), "accent": Color(0.16, 0.26, 0.66), "glow": Color(0.35, 0.8, 1.0)},
	"ionia_isle": {"name": "Floating Isle", "main": Color(0.9, 0.86, 0.74), "accent": Color(0.3, 0.5, 0.25), "glow": Color(0.35, 0.8, 1.0)},
	"ionia_star": {"name": "Wave Star", "main": Color(0.9, 0.86, 0.74), "accent": Color(0.16, 0.26, 0.66), "glow": Color(0.35, 0.8, 1.0)},
	"ionia_isles": {"name": "Three Isles", "main": Color(0.9, 0.86, 0.74), "accent": Color(0.3, 0.5, 0.25), "glow": Color(0.35, 0.8, 1.0)},
	"ionia_armillary": {"name": "Armillary", "main": Color(0.9, 0.86, 0.74), "accent": Color(0.88, 0.7, 0.3), "glow": Color(0.35, 0.8, 1.0)},
	"ionia_dome": {"name": "Hex Dome", "main": Color(0.9, 0.86, 0.74), "accent": Color(0.16, 0.26, 0.66), "glow": Color(0.35, 0.8, 1.0)},
	"ionia_column": {"name": "Column Gate", "main": Color(0.9, 0.86, 0.74), "accent": Color(0.16, 0.26, 0.66), "glow": Color(0.35, 0.8, 1.0)},
	"foundry": {"name": "Foundry", "main": WHITE, "accent": Color(0.75, 0.15, 0.12), "glow": Color(1.0, 0.6, 0.2)},
	# The Athenians' own (external/images/athenian_spacestations_1.png).
	"athens_parthenon": {"name": "Parthenon", "main": Color(0.88, 0.8, 0.6), "accent": Color(0.16, 0.22, 0.5), "glow": Color(0.35, 0.85, 1.0)},
	"athens_owl": {"name": "Owl of Athena", "main": Color(0.88, 0.8, 0.6), "accent": Color(0.16, 0.22, 0.5), "glow": Color(0.35, 0.85, 1.0)},
	"athens_athena": {"name": "Athena's Helm", "main": Color(0.88, 0.8, 0.6), "accent": Color(0.16, 0.22, 0.5), "glow": Color(0.35, 0.85, 1.0)},
	"athens_nike": {"name": "Nike's Wings", "main": Color(0.88, 0.8, 0.6), "accent": Color(0.16, 0.22, 0.5), "glow": Color(0.35, 0.85, 1.0)},
	"athens_olive": {"name": "Olive Wreath", "main": Color(0.88, 0.8, 0.6), "accent": Color(0.16, 0.22, 0.5), "glow": Color(0.35, 0.85, 1.0)},
	"athens_propylaia": {"name": "Propylaia", "main": Color(0.88, 0.8, 0.6), "accent": Color(0.16, 0.22, 0.5), "glow": Color(0.35, 0.85, 1.0)},
	"athens_agora": {"name": "Agora Ring", "main": Color(0.88, 0.8, 0.6), "accent": Color(0.16, 0.22, 0.5), "glow": Color(0.35, 0.85, 1.0)},
	"athens_trireme": {"name": "Trireme Dock", "main": Color(0.88, 0.8, 0.6), "accent": Color(0.16, 0.22, 0.5), "glow": Color(0.35, 0.85, 1.0)},
	"athens_aegis": {"name": "Aegis", "main": Color(0.88, 0.8, 0.6), "accent": Color(0.16, 0.22, 0.5), "glow": Color(0.35, 0.85, 1.0)},
	"athens_lyceum": {"name": "Lyceum", "main": Color(0.88, 0.8, 0.6), "accent": Color(0.16, 0.22, 0.5), "glow": Color(0.35, 0.85, 1.0)},
	"athens_theatre": {"name": "Theatre", "main": Color(0.88, 0.8, 0.6), "accent": Color(0.16, 0.22, 0.5), "glow": Color(0.35, 0.85, 1.0)},
	"athens_lighthouse": {"name": "Lighthouse Port", "main": Color(0.88, 0.8, 0.6), "accent": Color(0.16, 0.22, 0.5), "glow": Color(0.35, 0.85, 1.0)},
	# The Cycladic Isles' own (external/images/cycladic_spacestations_1.png).
	"cyclades_figure": {"name": "Colossal Figurine", "main": Color(0.92, 0.9, 0.85), "accent": Color(0.15, 0.3, 0.6), "glow": Color(0.25, 0.95, 0.9)},
	"cyclades_pan": {"name": "Spiral Pan", "main": Color(0.92, 0.9, 0.85), "accent": Color(0.15, 0.3, 0.6), "glow": Color(0.25, 0.95, 0.9)},
	"cyclades_circle": {"name": "Island Circle", "main": Color(0.92, 0.9, 0.85), "accent": Color(0.15, 0.3, 0.6), "glow": Color(0.25, 0.95, 0.9)},
	"cyclades_harbour": {"name": "Longboat Harbour", "main": Color(0.92, 0.9, 0.85), "accent": Color(0.15, 0.3, 0.6), "glow": Color(0.25, 0.95, 0.9)},
	"cyclades_spiral": {"name": "Marble Spiral", "main": Color(0.92, 0.9, 0.85), "accent": Color(0.15, 0.3, 0.6), "glow": Color(0.25, 0.95, 0.9)},
	"cyclades_quarry": {"name": "Marble Quarry", "main": Color(0.92, 0.9, 0.85), "accent": Color(0.15, 0.3, 0.6), "glow": Color(0.25, 0.95, 0.9)},
	"cyclades_obsidian": {"name": "Obsidian Forge", "main": Color(0.92, 0.9, 0.85), "accent": Color(0.15, 0.3, 0.6), "glow": Color(0.25, 0.95, 0.9)},
	"cyclades_harp": {"name": "Harp Station", "main": Color(0.92, 0.9, 0.85), "accent": Color(0.15, 0.3, 0.6), "glow": Color(0.25, 0.95, 0.9)},
	"cyclades_kandila": {"name": "Kandila Jar", "main": Color(0.92, 0.9, 0.85), "accent": Color(0.15, 0.3, 0.6), "glow": Color(0.25, 0.95, 0.9)},
	"cyclades_sanctuary": {"name": "Sanctuary of Figures", "main": Color(0.92, 0.9, 0.85), "accent": Color(0.15, 0.3, 0.6), "glow": Color(0.25, 0.95, 0.9)},
	"cyclades_sun": {"name": "Marble Sun", "main": Color(0.92, 0.9, 0.85), "accent": Color(0.15, 0.3, 0.6), "glow": Color(0.25, 0.95, 0.9)},
	"cyclades_lighthouse": {"name": "Island Beacon", "main": Color(0.92, 0.9, 0.85), "accent": Color(0.15, 0.3, 0.6), "glow": Color(0.25, 0.95, 0.9)},
	# The Mycenaeans' own (external/images/mycenaean_spacestations_1.png).
	"mycenae_lion_gate": {"name": "Lion Gate", "main": Color(0.72, 0.66, 0.55), "accent": Color(0.85, 0.65, 0.2), "glow": Color(1.0, 0.7, 0.25)},
	"mycenae_mask": {"name": "Golden Mask", "main": Color(0.72, 0.66, 0.55), "accent": Color(0.85, 0.65, 0.2), "glow": Color(1.0, 0.7, 0.25)},
	"mycenae_tholos": {"name": "Tholos", "main": Color(0.72, 0.66, 0.55), "accent": Color(0.85, 0.65, 0.2), "glow": Color(1.0, 0.7, 0.25)},
	"mycenae_megaron": {"name": "Megaron", "main": Color(0.72, 0.66, 0.55), "accent": Color(0.85, 0.65, 0.2), "glow": Color(1.0, 0.7, 0.25)},
	"mycenae_cyclopean": {"name": "Cyclopean Ring", "main": Color(0.72, 0.66, 0.55), "accent": Color(0.85, 0.65, 0.2), "glow": Color(1.0, 0.7, 0.25)},
	"mycenae_shield": {"name": "Figure-Eight Shield", "main": Color(0.72, 0.66, 0.55), "accent": Color(0.85, 0.65, 0.2), "glow": Color(1.0, 0.7, 0.25)},
	"mycenae_boar": {"name": "Boar's Tusk", "main": Color(0.72, 0.66, 0.55), "accent": Color(0.85, 0.65, 0.2), "glow": Color(1.0, 0.7, 0.25)},
	"mycenae_chariot": {"name": "Chariot Wheel", "main": Color(0.72, 0.66, 0.55), "accent": Color(0.85, 0.65, 0.2), "glow": Color(1.0, 0.7, 0.25)},
	"mycenae_griffin": {"name": "Griffin Shrine", "main": Color(0.72, 0.66, 0.55), "accent": Color(0.85, 0.65, 0.2), "glow": Color(1.0, 0.7, 0.25)},
	"mycenae_forge": {"name": "Shipwright's Forge", "main": Color(0.72, 0.66, 0.55), "accent": Color(0.85, 0.65, 0.2), "glow": Color(1.0, 0.7, 0.25)},
	"mycenae_treasury": {"name": "Treasury", "main": Color(0.72, 0.66, 0.55), "accent": Color(0.85, 0.65, 0.2), "glow": Color(1.0, 0.7, 0.25)},
	"mycenae_mine": {"name": "Mining Hub", "main": Color(0.72, 0.66, 0.55), "accent": Color(0.85, 0.65, 0.2), "glow": Color(1.0, 0.7, 0.25)},
	# The Spartans' own (external/images/spartan_spacestations_1.png).
	"sparta_lambda": {"name": "Lambda Fortress", "main": Color(0.85, 0.8, 0.7), "accent": Color(0.6, 0.1, 0.08), "glow": Color(1.0, 0.55, 0.2)},
	"sparta_helmet": {"name": "Helmet Citadel", "main": Color(0.85, 0.8, 0.7), "accent": Color(0.6, 0.1, 0.08), "glow": Color(1.0, 0.55, 0.2)},
	"sparta_hoplon": {"name": "Hoplon", "main": Color(0.85, 0.8, 0.7), "accent": Color(0.6, 0.1, 0.08), "glow": Color(1.0, 0.55, 0.2)},
	"sparta_phalanx": {"name": "Phalanx Ring", "main": Color(0.85, 0.8, 0.7), "accent": Color(0.6, 0.1, 0.08), "glow": Color(1.0, 0.55, 0.2)},
	"sparta_citadel": {"name": "Citadel", "main": Color(0.85, 0.8, 0.7), "accent": Color(0.6, 0.1, 0.08), "glow": Color(1.0, 0.55, 0.2)},
	"sparta_arsenal": {"name": "Arsenal", "main": Color(0.85, 0.8, 0.7), "accent": Color(0.6, 0.1, 0.08), "glow": Color(1.0, 0.55, 0.2)},
	"sparta_agoge": {"name": "Agoge", "main": Color(0.85, 0.8, 0.7), "accent": Color(0.6, 0.1, 0.08), "glow": Color(1.0, 0.55, 0.2)},
	"sparta_thermopylae": {"name": "Thermopylae", "main": Color(0.85, 0.8, 0.7), "accent": Color(0.6, 0.1, 0.08), "glow": Color(1.0, 0.55, 0.2)},
	"sparta_dory": {"name": "Dory", "main": Color(0.85, 0.8, 0.7), "accent": Color(0.6, 0.1, 0.08), "glow": Color(1.0, 0.55, 0.2)},
	"sparta_barracks": {"name": "Barracks", "main": Color(0.85, 0.8, 0.7), "accent": Color(0.6, 0.1, 0.08), "glow": Color(1.0, 0.55, 0.2)},
	"sparta_forge": {"name": "War Forge", "main": Color(0.85, 0.8, 0.7), "accent": Color(0.6, 0.1, 0.08), "glow": Color(1.0, 0.55, 0.2)},
	"sparta_watchtower": {"name": "Watchtower", "main": Color(0.85, 0.8, 0.7), "accent": Color(0.6, 0.1, 0.08), "glow": Color(1.0, 0.55, 0.2)},
	# The Minoans' own (external/images/minoan_spacestations_1.png).
	"minoa_palace": {"name": "Orbital Palace", "main": Color(0.93, 0.85, 0.72), "accent": Color(0.75, 0.22, 0.14), "glow": Color(0.35, 0.85, 1.0)},
	"minoa_horns": {"name": "Horns of Consecration", "main": Color(0.93, 0.85, 0.72), "accent": Color(0.75, 0.22, 0.14), "glow": Color(0.35, 0.85, 1.0)},
	"minoa_labrys": {"name": "Labrys", "main": Color(0.93, 0.85, 0.72), "accent": Color(0.75, 0.22, 0.14), "glow": Color(0.35, 0.85, 1.0)},
	"minoa_octopus": {"name": "Octopus", "main": Color(0.93, 0.85, 0.72), "accent": Color(0.75, 0.22, 0.14), "glow": Color(0.35, 0.85, 1.0)},
	"minoa_dolphins": {"name": "Dolphin Ring", "main": Color(0.93, 0.85, 0.72), "accent": Color(0.2, 0.45, 0.65), "glow": Color(0.35, 0.85, 1.0)},
	"minoa_spiral": {"name": "Great Spiral", "main": Color(0.93, 0.85, 0.72), "accent": Color(0.75, 0.22, 0.14), "glow": Color(0.35, 0.85, 1.0)},
	"minoa_lily": {"name": "Lily", "main": Color(0.93, 0.85, 0.72), "accent": Color(0.9, 0.55, 0.15), "glow": Color(0.35, 0.85, 1.0)},
	"minoa_nautilus": {"name": "Nautilus Laboratory", "main": Color(0.93, 0.85, 0.72), "accent": Color(0.2, 0.45, 0.65), "glow": Color(0.35, 0.85, 1.0)},
	"minoa_rosette": {"name": "Rosette", "main": Color(0.93, 0.85, 0.72), "accent": Color(0.45, 0.3, 0.7), "glow": Color(0.6, 0.45, 1.0)},
	"minoa_bull": {"name": "Bull's Head", "main": Color(0.93, 0.85, 0.72), "accent": Color(0.75, 0.22, 0.14), "glow": Color(0.35, 0.85, 1.0)},
	"minoa_wave": {"name": "Wave Ring", "main": Color(0.93, 0.85, 0.72), "accent": Color(0.2, 0.45, 0.65), "glow": Color(0.35, 0.85, 1.0)},
	"minoa_meander": {"name": "Meander Fortress", "main": Color(0.93, 0.85, 0.72), "accent": Color(0.75, 0.22, 0.14), "glow": Color(0.35, 0.85, 1.0)},
}

## Which designs each empire builds (a station picks one by its id) - matched
## to the empire's colours: Minoan cream and terracotta, Athenian sandstone and navy, Spartan crimson and bone, Mycenaean stone and gold (their own sheets),
## Spartan red, Mycenaean gold and bronze, the pirates' violet scythes.
const BY_EMPIRE := {"athens": ["athens_parthenon", "athens_owl", "athens_athena", "athens_nike", "athens_olive", "athens_propylaia",
		"athens_agora", "athens_trireme", "athens_aegis", "athens_lyceum", "athens_theatre", "athens_lighthouse"], "sparta": ["sparta_lambda", "sparta_helmet", "sparta_hoplon", "sparta_phalanx", "sparta_citadel", "sparta_arsenal",
		"sparta_agoge", "sparta_thermopylae", "sparta_dory", "sparta_barracks", "sparta_forge", "sparta_watchtower"],
	"minoa": ["minoa_palace", "minoa_horns", "minoa_labrys", "minoa_octopus", "minoa_dolphins", "minoa_spiral",
		"minoa_lily", "minoa_nautilus", "minoa_rosette", "minoa_bull", "minoa_wave", "minoa_meander"], "mycenae": ["mycenae_lion_gate", "mycenae_mask", "mycenae_tholos", "mycenae_megaron", "mycenae_cyclopean", "mycenae_shield",
		"mycenae_boar", "mycenae_chariot", "mycenae_griffin", "mycenae_forge", "mycenae_treasury", "mycenae_mine"], "pirates": ["vortex"],
	"cyclades": ["cyclades_figure", "cyclades_pan", "cyclades_circle", "cyclades_harbour", "cyclades_spiral", "cyclades_quarry",
		"cyclades_obsidian", "cyclades_harp", "cyclades_kandila", "cyclades_sanctuary", "cyclades_sun", "cyclades_lighthouse"],
	"independent": ["lotus", "violet_sun", "star", "solar", "halo", "crescents", "foundry", "forge", "gateway", "wheel", "trident"],   # (the empires' old designs: free ports now)
	"ionia": ["ionia_lyre", "ionia_garden", "ionia_waves", "ionia_laurel", "ionia_crescent", "ionia_pegasus",
		"ionia_isle", "ionia_star", "ionia_isles", "ionia_armillary", "ionia_dome", "ionia_column"]}



static func design_for(empire: String, station_id: String) -> String:
	var opts: Array = BY_EMPIRE.get(empire, BY_EMPIRE["athens"])
	return opts[absi(hash(station_id)) % opts.size()]


static func ids() -> Array:
	return DESIGNS.keys()
