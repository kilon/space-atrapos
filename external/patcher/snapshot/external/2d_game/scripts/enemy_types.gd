class_name EnemyTypes
## AI ship catalogue. Every ship flying in the game is one of the hand-traced
## designs (TracedShips, listed by ShipDesigns): hostile combat classes,
## neutral traders / miners / explorers, and the empires' own designs. The two
## main-quest bosses reuse the biggest traced hulls, scaled up and tinted.
##
## Keys: name, length (on-screen size in pixels along the ship's nose-to-tail
## axis; the player's ship is ~116, so others are never smaller), hull,
## shields, speed, fire_interval, damage, bullet_speed, shots (bolts per
## volley, spread out), aggro, distance (preferred fighting distance), color
## (laser colour), art (the design a type is drawn with, if not its own id).

## Ships are never drawn smaller than the player ship.
const MIN_LENGTH := 116.0
## Used for ship ids that no longer exist (e.g. in old save games).
const FALLBACK := "traced_ember"

## Main-quest bosses (unique: never spawned randomly).
const BOSSES := {
	"asterion": {
		"name": "Asterion, the Bull of Minos", "unique": true, "art": "traced_bastion",
		"desc": "Pirate warlord who took the Minotaur's name. His red-bronze flagship guards the approach to the Labyrinth.",
		"length": 290.0, "tint": Color(1.0, 0.7, 0.62),
		"hull": 700.0, "shields": 320.0, "speed": 120.0, "fire_interval": 0.9, "damage": 12.0,
		"bullet_speed": 650.0, "shots": 5, "aggro": 900.0, "distance": 450.0,
		"color": Color(1.0, 0.3, 0.2),
	},
	"talos": {
		"name": "Talos, the Bronze Guardian", "unique": true, "art": "traced_bulwark",
		"desc": "A colossal bronze automaton that guards the Labyrinth. Its shields recover quickly - keep up the pressure.",
		"length": 400.0, "tint": Color(1.0, 0.72, 0.42),
		"hull": 1000.0, "shields": 450.0, "speed": 95.0, "fire_interval": 1.0, "damage": 15.0,
		"bullet_speed": 620.0, "shots": 5, "aggro": 1000.0, "distance": 480.0,
		"color": Color(1.0, 0.65, 0.25), "shield_regen": 30.0, "shield_delay": 2.5,
	},
}

## Alien creatures (signal sites - SignalSite "monster"): unique, never
## spawned at random; drawn as a SpaceMonster instead of a ship ("art" only
## sizes them). They attack in bullet-hell patterns of energy orbs (SpaceMonster).
const MONSTERS := {
	"void_leviathan": {
		"name": "Void Leviathan", "unique": true, "monster": true, "art": "traced_bastion",
		"desc": "A vast creature that swims between the stars. Its hide is laced with alien alloy.",
		"length": 300.0, "hull": 950.0, "shields": 0.0, "speed": 150.0, "fire_interval": 1.3, "damage": 14.0,
		"bullet_speed": 520.0, "shots": 3, "aggro": 950.0, "distance": 520.0,
		"color": Color(0.45, 1.0, 0.45),
	},
	# The monster signal's creature (SeaWitch): a sea witch rising from eight tentacles.
	"skylla": {
		"name": "Skylla", "unique": true, "monster": true, "look": "sea_witch", "art": "traced_bastion",
		"desc": "A sea witch of the deep void: a woman crowned in gold, rising from eight great tentacles. She sweeps them at whatever comes close and spits clouds of ink that drag your ship to a crawl.",
		"length": 380.0, "hull": 2800.0, "shields": 800.0, "speed": 140.0, "fire_interval": 1.3, "damage": 14.0,
		"bullet_speed": 520.0, "shots": 3, "aggro": 950.0, "distance": 560.0,
		"color": Color(1.0, 0.4, 0.75), "shield_regen": 40.0, "shield_delay": 3.0,
	},
	# A monster-signal creature (CerberusBeast): the three-headed hound.
	"cerberus": {
		"name": "Cerberus", "unique": true, "monster": true, "look": "cerberus", "art": "traced_bastion",
		"desc": "The three-headed hound of the underworld, armoured in gold and the sign of the temple. All three heads breathe fire at once, and it pounces.",
		"length": 400.0, "hull": 2800.0, "shields": 800.0, "speed": 150.0, "fire_interval": 1.3, "damage": 14.0,
		"bullet_speed": 520.0, "shots": 3, "aggro": 950.0, "distance": 560.0,
		"color": Color(1.0, 0.5, 0.15), "shield_regen": 40.0, "shield_delay": 3.0,
	},
	# A monster-signal creature (CetusBeast): the sea monster Poseidon sent against Andromeda.
	"cetus": {
		"name": "Cetus", "unique": true, "monster": true, "look": "cetus", "art": "traced_bastion",
		"desc": "The sea monster Poseidon sent against Andromeda: a vast armoured whale-serpent. It raises rings of breaking waves, and dives into the void to breach beneath you.",
		"length": 480.0, "hull": 3000.0, "shields": 800.0, "speed": 170.0, "fire_interval": 1.3, "damage": 14.0,
		"bullet_speed": 520.0, "shots": 3, "aggro": 1000.0, "distance": 620.0,
		"color": Color(0.25, 0.6, 1.0), "shield_regen": 40.0, "shield_delay": 3.0,
	},
	# A monster-signal creature (EchidnaBeast): the mother of monsters.
	"echidna": {
		"name": "Echidna", "unique": true, "monster": true, "look": "echidna", "art": "traced_bastion",
		"desc": "The mother of monsters: half woman, half serpent, coiled in gold-banded scales. She looses her brood of serpents after you and spits venom that burns where it lands.",
		"length": 400.0, "hull": 2900.0, "shields": 800.0, "speed": 150.0, "fire_interval": 1.3, "damage": 14.0,
		"bullet_speed": 520.0, "shots": 3, "aggro": 950.0, "distance": 580.0,
		"color": Color(0.55, 1.0, 0.25), "shield_regen": 40.0, "shield_delay": 3.0,
	},
	# A monster-signal creature (HydraBeast): the many-headed serpent of Lerna.
	"hydra": {
		"name": "The Hydra", "unique": true, "monster": true, "look": "hydra", "art": "traced_bastion",
		"desc": "The many-headed serpent of Lerna: eight heads on one knot of coils, each spitting venom. Cut one off and it grows back. It bites, and it breathes poison.",
		"length": 460.0, "hull": 3000.0, "shields": 800.0, "speed": 150.0, "fire_interval": 1.3, "damage": 14.0,
		"bullet_speed": 520.0, "shots": 3, "aggro": 1000.0, "distance": 600.0,
		"color": Color(0.4, 0.8, 0.2), "shield_regen": 40.0, "shield_delay": 3.0,
	},
	# The Hydra's double head (HydraHead): two heads on one neck, grown where one was cut.
	"hydra_head": {
		"name": "Hydra Double Head", "unique": true, "monster": true, "look": "hydra_head", "art": "traced_bastion",
		"desc": "Cut off one of the Hydra's heads and two grow back: a double head on its own neck, keeping round the Hydra and spitting fangs and venom from both jaws. It dies with the Hydra.",
		"length": 150.0, "hull": 300.0, "shields": 0.0, "speed": 150.0, "fire_interval": 1.3, "damage": 10.0,
		"bullet_speed": 520.0, "shots": 1, "aggro": 1000.0, "distance": 400.0,
		"color": Color(0.4, 0.8, 0.2),
	},
	# A monster-signal creature (ChimeraBeast): lion, goat and serpent in one.
	"chimera": {
		"name": "The Chimera", "unique": true, "monster": true, "look": "chimera", "art": "traced_bastion",
		"desc": "Lion in front, a goat's head rising from its back, a serpent for a tail: each head fights its own way - fire, embers and venom. The lion breathes a sweeping cone of fire; the goat charges with lowered horns.",
		"length": 440.0, "hull": 3000.0, "shields": 800.0, "speed": 160.0, "fire_interval": 1.3, "damage": 14.0,
		"bullet_speed": 520.0, "shots": 3, "aggro": 1000.0, "distance": 600.0,
		"color": Color(1.0, 0.45, 0.1), "shield_regen": 40.0, "shield_delay": 3.0,
	},
	# A monster-signal creature (CharybdisBeast): the whirlpool that swallows the sea.
	"charybdis": {
		"name": "Charybdis", "unique": true, "monster": true, "look": "charybdis", "art": "traced_bastion",
		"desc": "The whirlpool that swallows the sea and spews it out again: a ring of teeth round a turning vortex, tentacles writhing at its rim. It drags you toward its maw.",
		"length": 460.0, "hull": 3000.0, "shields": 800.0, "speed": 130.0, "fire_interval": 1.3, "damage": 14.0,
		"bullet_speed": 520.0, "shots": 3, "aggro": 1000.0, "distance": 650.0,
		"color": Color(0.25, 0.6, 1.0), "shield_regen": 40.0, "shield_delay": 3.0,
	},
	# The main quest's last boss (MinotaurBoss): the true Asterion, guardian of the Labyrinth.
	"minotaur": {
		"name": "The Minotaur", "unique": true, "monster": true, "look": "minotaur", "art": "traced_bulwark",
		"desc": "The true Asterion: the bull-headed guardian of the Labyrinth, crowned in bronze, awake after three thousand years. He charges, sears with a beam from his crest and drains your shields with a golden pulse.",
		"length": 420.0, "hull": 5000.0, "shields": 1500.0, "speed": 120.0, "fire_interval": 1.3, "damage": 16.0,
		"bullet_speed": 520.0, "shots": 3, "aggro": 1100.0, "distance": 600.0,
		"color": Color(1.0, 0.32, 0.15), "shield_regen": 60.0, "shield_delay": 3.0,
	},
}

static var _all := {}


## Every ship type: the traced classes plus the bosses.
static func types() -> Dictionary:
	if _all.is_empty():
		_all = ShipDesigns.types().duplicate()
		_all.merge(BOSSES)
		_all.merge(MONSTERS)
	return _all


static func has_type(id: String) -> bool:
	return types().has(id)


## Hostile ship classes.
static func ids() -> Array:
	var t := types()
	return t.keys().filter(func(id): return t[id].get("faction", "enemy") == "enemy" and not t[id].get("unique", false))


## Neutral (civilian) ship classes.
static func neutral_ids() -> Array:
	var t := types()
	return t.keys().filter(func(id): return t[id].get("faction", "enemy") == "neutral")


static func get_type(id: String) -> Dictionary:
	var t := types()
	return t.get(id, t[FALLBACK])


static func all_ids() -> Array:
	return types().keys()


## The ship's picture (vector art baked by ProcArt).
static func texture(id: String) -> Texture2D:
	var tree := Engine.get_main_loop() as SceneTree
	var art: Node = tree.root.get_node_or_null("ProcArt") if tree else null
	if art == null:
		return null
	return art.ship_texture(id if has_type(id) else FALLBACK)
