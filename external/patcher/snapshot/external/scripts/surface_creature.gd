class_name SurfaceCreature
extends SurfaceProps.Thing
## Wildlife on a planet's surface: Greek animals in 1980s anime style (sprites
## data/sprites/creature_<set>_<species>_<pose>, cut from
## external/images/forest_creatures.png by tools/extract_sprites.py; poses
## stand, move_a / move_b (a walk, hop, slither or wingbeat) and act - each
## species' special pose: grazing, alert, braying, sitting, hiding in its shell,
## lunging). All are drawn facing down-left; mirrored when they head right.
##
## Tempers:
##   grazer    strolls about its home, grazes; runs off if you come close (the
##             shy ones) or shoot at it
##   skittish  bolts from you
##   slow      the tortoise: hides in its shell while you're near
##   bird      the owl: perches, flies off when you come near (and now and then)
##   soar      the eagle: circles high over its home, sometimes lands (the
##             aeromanta glides lower and never lands)
##   drift     the sky jelly: floats about at head height, pulsing
##   (fights)  big grazers with horns, antlers or tusks ("fights": true) turn on
##             whoever hurts them instead of running
##   predator  wolves, boars and snakes: they go for you when you come within
##             their sense (and can see you), bite in reach; hostile - you shoot
##             them like pirates (group "surface_hostiles"); pack hunters
##             (wolves, harpyxes) call their pack, and badly hurt ones run;
##             chargers (boar, hoplorhino) charge
## Predators also hunt other animals when hungry (anything not of their kind,
## no bigger than them, on the ground); the hunted run, hide or fight back.
## Any animal can be shot; a fallen one leaves Cybernetic Matter (a chest).
## PlanetSurface plans them across the planet (_plan_fauna) and streams them
## in and out around you (_stream_fauna).

## Per species: name, height on screen (px, standing), walk / run speeds (px/s),
## temper, how near you may come (shy, px; 0: tame), health; predators: bite,
## reach and sense (px), s between bites.
## The volcanic beasts: FIERCE_HP times their "like"'s health, FIERCE times its bite.
const FIERCE := 2.0
const FIERCE_HP := 4.0
const SPECIES := {
	"goat": {"name": "Cretan wild goat", "h": 74.0, "walk": 40.0, "run": 150.0, "temper": "grazer", "shy": 260.0, "hp": 30.0, "fights": true, "bite": 6.0, "reach": 46.0, "every": 1.1},
	"sheep": {"name": "sheep", "h": 58.0, "walk": 28.0, "run": 90.0, "temper": "grazer", "shy": 0.0, "hp": 30.0},
	"deer": {"name": "red deer", "h": 118.0, "walk": 45.0, "run": 170.0, "temper": "grazer", "shy": 340.0, "hp": 40.0, "fights": true, "bite": 8.0, "reach": 52.0, "every": 1.2},
	"donkey": {"name": "donkey", "h": 96.0, "walk": 30.0, "run": 80.0, "temper": "grazer", "shy": 0.0, "hp": 50.0, "fights": true, "bite": 7.0, "reach": 50.0, "every": 1.4},
	"hare": {"name": "brown hare", "h": 34.0, "walk": 50.0, "run": 210.0, "temper": "skittish", "shy": 280.0, "hp": 10.0},
	"fox": {"name": "red fox", "h": 46.0, "walk": 55.0, "run": 180.0, "temper": "skittish", "shy": 300.0, "hp": 20.0},
	"tortoise": {"name": "Greek tortoise", "h": 24.0, "walk": 9.0, "run": 9.0, "temper": "slow", "shy": 140.0, "hp": 40.0},
	"owl": {"name": "little owl", "h": 30.0, "walk": 0.0, "run": 170.0, "temper": "bird", "shy": 220.0, "hp": 10.0},
	"eagle": {"name": "golden eagle", "h": 56.0, "walk": 0.0, "run": 120.0, "temper": "soar", "shy": 200.0, "hp": 30.0},
	"wolf": {"name": "grey wolf", "h": 66.0, "walk": 45.0, "run": 165.0, "temper": "predator", "hp": 45.0, "pack": true, "flees": true,
		"bite": 5.0, "reach": 46.0, "sense": 420.0, "every": 1.0},
	"boar": {"name": "wild boar", "h": 62.0, "walk": 35.0, "run": 205.0, "temper": "predator", "hp": 60.0, "charge": true,
		"bite": 14.0, "reach": 50.0, "sense": 260.0, "every": 1.4},
	"snake": {"name": "Aesculapian snake", "h": 26.0, "walk": 22.0, "run": 30.0, "temper": "predator", "hp": 15.0, "coiled": true,
		"bite": 7.0, "reach": 70.0, "sense": 120.0, "every": 1.2},
	# The alien beasts (external/images/forest_creatures_2.png).
	"tigrokeros": {"name": "striped tigrokeros", "h": 76.0, "walk": 42.0, "run": 160.0, "temper": "grazer", "shy": 280.0, "hp": 35.0, "fights": true, "bite": 7.0, "reach": 48.0, "every": 1.1},
	"mykelephas": {"name": "mushroom mammoth", "h": 130.0, "walk": 24.0, "run": 60.0, "temper": "grazer", "shy": 0.0, "hp": 120.0, "fights": true, "charge": true, "bite": 16.0, "reach": 66.0, "every": 1.6},
	"selas": {"name": "glowing selas stag", "h": 116.0, "walk": 44.0, "run": 175.0, "temper": "grazer", "shy": 360.0, "hp": 40.0, "fights": true, "bite": 9.0, "reach": 52.0, "every": 1.2},
	"capslug": {"name": "capped slug", "h": 66.0, "walk": 12.0, "run": 12.0, "temper": "grazer", "shy": 0.0, "hp": 50.0},
	"toad": {"name": "bubble toad", "h": 40.0, "walk": 40.0, "run": 170.0, "temper": "skittish", "shy": 220.0, "hp": 12.0},
	"pangolin": {"name": "moss pangolin", "h": 40.0, "walk": 20.0, "run": 20.0, "temper": "slow", "shy": 160.0, "hp": 50.0},
	"aeromanta": {"name": "aeromanta", "h": 50.0, "walk": 0.0, "run": 140.0, "temper": "soar", "shy": 0.0, "hp": 30.0,
		"alt": 110.0, "lands": false},
	"jelly": {"name": "sky jelly", "h": 70.0, "walk": 14.0, "run": 14.0, "temper": "drift", "shy": 0.0, "hp": 20.0, "alt": 46.0},
	"harpyx": {"name": "harpyx raptor", "h": 82.0, "walk": 50.0, "run": 175.0, "temper": "predator", "hp": 50.0, "pack": true, "flees": true,
		"bite": 6.0, "reach": 50.0, "sense": 380.0, "every": 0.9},
	"hoplorhino": {"name": "hoplorhino", "h": 88.0, "walk": 28.0, "run": 190.0, "temper": "predator", "hp": 130.0, "charge": true,
		"bite": 18.0, "reach": 60.0, "sense": 240.0, "every": 1.6},
	"mantis": {"name": "giant mantis", "h": 80.0, "walk": 30.0, "run": 120.0, "temper": "predator", "hp": 40.0,
		"bite": 9.0, "reach": 64.0, "sense": 200.0, "every": 1.0},
	"drakaina": {"name": "drakaina serpent", "h": 62.0, "walk": 26.0, "run": 60.0, "temper": "predator", "hp": 45.0, "coiled": true,
		"bite": 10.0, "reach": 80.0, "sense": 190.0, "every": 1.3},
	# The giant insects (external/images/forest_creatures_3.png).
	"scarab": {"name": "horned scarab", "h": 54.0, "walk": 22.0, "run": 60.0, "temper": "grazer", "shy": 0.0, "hp": 40.0, "fights": true, "bite": 6.0, "reach": 46.0, "every": 1.2},
	"rhinobeetle": {"name": "rhinoceros beetle", "h": 58.0, "walk": 24.0, "run": 60.0, "temper": "grazer", "shy": 0.0, "hp": 45.0, "fights": true, "charge": true, "bite": 9.0, "reach": 50.0, "every": 1.3},
	"pillbug": {"name": "mushroom pillbug", "h": 48.0, "walk": 16.0, "run": 16.0, "temper": "slow", "shy": 150.0, "hp": 50.0},
	"leafbug": {"name": "leaf bug", "h": 46.0, "walk": 20.0, "run": 20.0, "temper": "slow", "shy": 170.0, "hp": 30.0},
	"moth": {"name": "peacock moth", "h": 52.0, "walk": 30.0, "run": 30.0, "temper": "drift", "shy": 0.0, "hp": 8.0, "alt": 60.0},
	"firefly": {"name": "lantern firefly", "h": 40.0, "walk": 26.0, "run": 26.0, "temper": "drift", "shy": 0.0, "hp": 6.0, "alt": 52.0},
	"dragonfly": {"name": "dragonfly", "h": 44.0, "walk": 0.0, "run": 170.0, "temper": "soar", "shy": 0.0, "hp": 8.0,
		"alt": 80.0, "lands": false, "circle": 140.0},
	"spider": {"name": "jumping spider", "h": 46.0, "walk": 30.0, "run": 190.0, "temper": "predator", "hp": 30.0,
		"bite": 7.0, "reach": 50.0, "sense": 260.0, "every": 1.1},
	"centipede": {"name": "giant centipede", "h": 40.0, "walk": 34.0, "run": 140.0, "temper": "predator", "hp": 35.0,
		"bite": 8.0, "reach": 56.0, "sense": 200.0, "every": 1.1},
	"phasma": {"name": "stick mantis", "h": 74.0, "walk": 26.0, "run": 110.0, "temper": "predator", "hp": 35.0,
		"bite": 9.0, "reach": 64.0, "sense": 170.0, "every": 1.0},
	"mykospider": {"name": "fungal stalker", "h": 62.0, "walk": 22.0, "run": 150.0, "temper": "predator", "hp": 55.0,
		"bite": 11.0, "reach": 64.0, "sense": 150.0, "every": 1.3},
	"grub": {"name": "glass grub", "h": 40.0, "walk": 14.0, "run": 40.0, "temper": "predator", "hp": 40.0,
		"bite": 9.0, "reach": 60.0, "sense": 110.0, "every": 1.4},
	# The ice planets' crystal beasts (external/images/ice_creatures.png; sprites creature_ic_*).
	"icestag": {"name": "crystal stag", "h": 100.0, "walk": 42.0, "run": 170.0, "temper": "grazer", "shy": 320.0, "hp": 40.0, "fights": true, "bite": 8.0, "reach": 52.0, "every": 1.2},
	"shardcrawler": {"name": "shard crawler", "h": 46.0, "walk": 14.0, "run": 14.0, "temper": "grazer", "shy": 0.0, "hp": 50.0},
	"icehare": {"name": "frost-winged hare", "h": 44.0, "walk": 46.0, "run": 210.0, "temper": "skittish", "shy": 260.0, "hp": 10.0},
	"starcrawler": {"name": "star crawler", "h": 54.0, "walk": 18.0, "run": 18.0, "temper": "slow", "shy": 150.0, "hp": 45.0},
	"frostray": {"name": "frost ray", "h": 56.0, "walk": 0.0, "run": 150.0, "temper": "soar", "shy": 0.0, "hp": 25.0,
		"alt": 90.0, "lands": false, "circle": 180.0},
	"wisp": {"name": "ice wisp", "h": 56.0, "walk": 16.0, "run": 16.0, "temper": "drift", "shy": 0.0, "hp": 15.0, "alt": 50.0},
	"frostbeast": {"name": "frost behemoth", "h": 100.0, "walk": 26.0, "run": 185.0, "temper": "predator", "hp": 140.0, "charge": true,
		"bite": 18.0, "reach": 62.0, "sense": 240.0, "every": 1.6},
	"frostwolf": {"name": "crystal wolf", "h": 70.0, "walk": 45.0, "run": 165.0, "temper": "predator", "hp": 45.0, "pack": true, "flees": true,
		"bite": 5.0, "reach": 48.0, "sense": 420.0, "every": 1.0},
	"strider": {"name": "crystal strider", "h": 96.0, "walk": 34.0, "run": 180.0, "temper": "predator", "hp": 50.0,
		"bite": 9.0, "reach": 70.0, "sense": 300.0, "every": 1.1},
	"scuttler": {"name": "frost scuttler", "h": 50.0, "walk": 26.0, "run": 130.0, "temper": "predator", "hp": 40.0,
		"bite": 8.0, "reach": 56.0, "sense": 160.0, "every": 1.2},
	"bubblespider": {"name": "bubble spider", "h": 56.0, "walk": 22.0, "run": 140.0, "temper": "predator", "hp": 40.0,
		"bite": 10.0, "reach": 64.0, "sense": 150.0, "every": 1.3},
	"icewyrm": {"name": "ice wyrm", "h": 64.0, "walk": 26.0, "run": 60.0, "temper": "predator", "hp": 50.0, "coiled": true,
		"bite": 11.0, "reach": 84.0, "sense": 200.0, "every": 1.3},
	# The volcanic planet's beasts (external/images/volcanic_creatures.png; sprites
	# creature_vo_*): big, alien and aggressive - every one a predator that comes
	# for you from far off. Each is modelled on a creature of the other planets
	# ("like") and has FIERCE_HP times its health and FIERCE times its bite.
	"magmabehemoth": {"name": "magma behemoth", "h": 190.0, "walk": 26.0, "run": 175.0, "temper": "predator", "like": "frostbeast", "hp": 560.0, "charge": true,
		"bite": 36.0, "reach": 90.0, "sense": 380.0, "every": 1.6},
	"cinderstalker": {"name": "cinder stalker", "h": 160.0, "walk": 46.0, "run": 200.0, "temper": "predator", "like": "strider", "hp": 200.0,
		"bite": 18.0, "reach": 84.0, "sense": 520.0, "every": 0.9},
	"obsidianmantis": {"name": "obsidian mantis", "h": 180.0, "walk": 32.0, "run": 150.0, "temper": "predator", "like": "mantis", "hp": 160.0,
		"bite": 18.0, "reach": 96.0, "sense": 340.0, "every": 1.0},
	"bloater": {"name": "sulphur bloater", "h": 160.0, "walk": 18.0, "run": 50.0, "temper": "predator", "like": "bubblespider", "hp": 160.0,
		"bite": 20.0, "reach": 130.0, "sense": 300.0, "every": 1.6},
	"lavaserpent": {"name": "lava serpent", "h": 170.0, "walk": 22.0, "run": 70.0, "temper": "predator", "like": "icewyrm", "hp": 200.0, "coiled": true,
		"bite": 22.0, "reach": 130.0, "sense": 320.0, "every": 1.4},
	"ventcrab": {"name": "vent crab", "h": 150.0, "walk": 24.0, "run": 140.0, "temper": "predator", "like": "hoplorhino", "hp": 520.0, "charge": true,
		"bite": 36.0, "reach": 84.0, "sense": 260.0, "every": 1.5},
	"pyrohound": {"name": "pyroclast hound", "h": 130.0, "walk": 50.0, "run": 195.0, "temper": "predator", "like": "frostwolf", "hp": 180.0, "pack": true,
		"bite": 10.0, "reach": 68.0, "sense": 520.0, "every": 0.9},
	"ashwraith": {"name": "ash wraith", "h": 170.0, "walk": 34.0, "run": 150.0, "temper": "predator", "like": "mykospider", "hp": 220.0,
		"bite": 22.0, "reach": 90.0, "sense": 440.0, "every": 1.1},
	"basaltgolem": {"name": "basalt golem", "h": 210.0, "walk": 20.0, "run": 120.0, "temper": "predator", "like": "mykelephas", "hp": 480.0, "charge": true,
		"bite": 32.0, "reach": 96.0, "sense": 300.0, "every": 1.8},
	"emberqueen": {"name": "ember swarm queen", "h": 160.0, "walk": 44.0, "run": 210.0, "temper": "predator", "like": "harpyx", "hp": 200.0,
		"bite": 12.0, "reach": 84.0, "sense": 560.0, "every": 1.0},
	"cratermaw": {"name": "crater maw", "h": 140.0, "walk": 22.0, "run": 110.0, "temper": "predator", "like": "grub", "hp": 160.0,
		"bite": 18.0, "reach": 100.0, "sense": 260.0, "every": 1.4},
	"fumaroletitan": {"name": "fumarole titan", "h": 220.0, "walk": 22.0, "run": 165.0, "temper": "predator", "like": "frostbeast", "hp": 560.0, "charge": true,
		"bite": 36.0, "reach": 100.0, "sense": 400.0, "every": 1.8},
}
## Which animals live on a terrain set's planets (PlanetSurface: pdata "tiles"):
## [species, groups, fewest, most, where] - "wild" away from the villages and
## the pad, "village" around them (herds kept), "any".
const FAUNA := {"fo": [
	["goat", 12, 2, 5, "wild"], ["sheep", 8, 2, 5, "village"], ["donkey", 6, 1, 2, "village"],
	["deer", 10, 1, 3, "wild"], ["hare", 16, 1, 2, "any"], ["fox", 8, 1, 1, "wild"],
	["tortoise", 12, 1, 1, "any"], ["owl", 10, 1, 1, "any"], ["eagle", 6, 1, 1, "wild"],
	["wolf", 7, 2, 4, "wild"], ["boar", 9, 1, 3, "wild"], ["snake", 12, 1, 1, "wild"],
	["tigrokeros", 8, 2, 4, "wild"], ["mykelephas", 6, 1, 3, "wild"], ["selas", 7, 1, 3, "wild"],
	["capslug", 8, 1, 2, "any"], ["toad", 12, 1, 3, "any"], ["pangolin", 10, 1, 1, "any"],
	["aeromanta", 6, 1, 2, "wild"], ["jelly", 8, 2, 4, "wild"], ["harpyx", 5, 2, 3, "wild"],
	["hoplorhino", 5, 1, 1, "wild"], ["mantis", 6, 1, 1, "wild"], ["drakaina", 5, 1, 1, "wild"],
	["scarab", 8, 1, 3, "any"], ["rhinobeetle", 7, 1, 2, "any"], ["pillbug", 8, 1, 2, "any"],
	["leafbug", 8, 1, 2, "any"], ["moth", 8, 1, 3, "any"], ["firefly", 8, 3, 6, "any"], ["dragonfly", 7, 1, 2, "any"],
	["spider", 5, 1, 2, "wild"], ["centipede", 5, 1, 1, "wild"], ["phasma", 4, 1, 1, "wild"],
	["mykospider", 4, 1, 1, "wild"], ["grub", 5, 1, 2, "wild"]],
	"ic": [
	["icestag", 10, 1, 3, "wild"], ["shardcrawler", 10, 1, 2, "any"], ["icehare", 14, 1, 2, "any"],
	["starcrawler", 10, 1, 1, "any"], ["frostray", 8, 1, 2, "any"], ["wisp", 10, 2, 4, "any"],
	["frostbeast", 5, 1, 1, "wild"], ["frostwolf", 7, 2, 4, "wild"], ["strider", 6, 1, 2, "wild"],
	["scuttler", 8, 1, 2, "wild"], ["bubblespider", 6, 1, 1, "wild"], ["icewyrm", 6, 1, 1, "wild"]],
	"vo": [
	["magmabehemoth", 4, 1, 1, "any"], ["cinderstalker", 5, 1, 2, "any"], ["obsidianmantis", 5, 1, 1, "any"],
	["bloater", 5, 1, 2, "any"], ["lavaserpent", 5, 1, 1, "any"], ["ventcrab", 5, 1, 2, "any"],
	["pyrohound", 5, 2, 4, "any"], ["ashwraith", 5, 1, 1, "any"], ["basaltgolem", 3, 1, 1, "any"],
	["emberqueen", 5, 1, 2, "any"], ["cratermaw", 5, 1, 1, "any"], ["fumaroletitan", 3, 1, 1, "any"]]}
const POSES := ["stand", "move_a", "move_b", "act"]
## Animals a planet has: its FAUNA table's groups times this.
const DENSITY := 2
const WANDER := 220.0              # px from home they stroll
const STRIDE := 46.0               # px a walk cycle (two frames)
const GRUDGE := 12.0               # s a predator goes after whoever shot it
const FLEE_HP := 0.25              # of hp: a hurt wolf runs
const SOAR_R := 320.0              # the eagle's circle (px)
const SOAR_ALT := 170.0            # its height (px)

var species := "goat"
var set_id := "fo"
var home := Vector2.ZERO
var surface: Node
var spec: Dictionary
var hp := 1.0
var max_hp := 1.0
var dead := false
var hostile := false
## (PlanetSurface: its plan, to note where it went / that it fell)
var plan: Dictionary
## Who hurt it last (you: it counts in your bestiary when it falls).
var last_by: Node2D

var _tex: Array = []               # the four poses
var _k := 1.0                      # sprite scale
var _pose := 0
var _right := false                # heading right (mirrored)
var _alt := 0.0                    # flying height (px)
var _state := "idle"               # idle / walk / act / flee / hide / chase / bite / fly / perch / soar / dive
var _t := 0.0                      # time in the state
var _wait := 1.0                   # idle: s until the next thing
var _goal := Vector2.ZERO
var _phase := 0.0
var _hurt := 0.0
var _threat: Node2D                # what it runs from / goes for
var _grudge := 0.0
var _cd := 0.0                     # s to the next bite
var _look := 0.0
var _ang := 0.0                    # the eagle's place on its circle
var _clock := 0.0
var _side := Vector2.ZERO          # a predator's side of its prey (a pack surrounds it)
var _hunger := 0.0                 # s until a predator goes hunting other animals


static func make(species_: String, set_ := "fo") -> SurfaceCreature:
	var c := SurfaceCreature.new()
	c.species = species_
	c.set_id = set_
	return c


func _ready() -> void:
	spec = SPECIES[species]
	max_hp = spec["hp"]
	hp = max_hp
	hostile = spec["temper"] == "predator"
	height = spec["h"]
	click_radius = maxf(30.0, spec["h"] * 0.6)
	var nm: String = spec["name"]
	title = nm.capitalize() + ("  -  right-click or F to fire" if hostile else "")
	if hostile:
		add_to_group("surface_hostiles")
	add_to_group("surface_creatures")
	for p in POSES:
		_tex.append(_texture("creature_%s_%s_%s" % [set_id, species, p]))
	if _tex[0]:
		_k = spec["h"] / _tex[0].get_height()
	_wait = randf_range(0.5, 4.0)
	_look = randf() * 0.3
	_ang = randf() * TAU
	_side = Vector2.from_angle(randf() * TAU) * Vector2(1.0, 0.5)
	_hunger = randf_range(8.0, 45.0)
	_right = randf() < 0.5
	if spec["temper"] == "soar":
		_go("soar")
		_alt = _soar_alt()
	elif spec["temper"] == "drift":
		_alt = spec["alt"]
	elif spec["temper"] == "bird":
		_go("perch")


static func _texture(key: String) -> Texture2D:
	var tree := Engine.get_main_loop() as SceneTree
	var art: Node = tree.root.get_node_or_null("ProcArt") if tree else null
	return art.sprite(key) if art else null   # (drawn as they are: a placeholder till the picture is in - ProcArt.sprite)


func _go(s: String) -> void:
	_state = s
	_t = 0.0
	_stuck_at = Vector2.INF
	_route = PackedVector2Array()


func _you() -> Node2D:
	return surface.get("pilot") if surface else null


## You, if it can go for you now (alive, on the ground floor, in sight).
func _you_near(r: float) -> Node2D:
	var you := _you()
	if you == null or (surface.has_method("pilot_targetable") and not surface.pilot_targetable()):
		return null
	return you if position.distance_to(you.position) < r else null


## Animals off the screen (and not fighting you) sleep: no _process of their
## own - the surface wakes a slice of its sleepers each frame (PlanetSurface.
## _tick_sleepers: each about every 8th frame, far ones every 16th) and they
## think with the time they slept: the same behaviour, a fraction of the
## cost (most of the animals out are off screen; each one's own _process,
## even returning at once, cost ~4 us a frame - 90 of them ~0.4 ms).
const FAR := 1500.0
var asleep := false
var _slept_at := 0.0                 # (the surface's clock when it last thought)
var _far_skip := false
var listed := false                  # (in the surface's sleepers: once only)

func _process(delta: float) -> void:
	if dead:
		return
	if _sleepy():
		asleep = true
		set_process(false)
		_slept_at = surface.clock
		if not listed:
			listed = true
			surface.sleepers.append(self)
		return
	_think(delta)


## Off the screen and not fighting - or far (beyond FAR px) whatever it's doing.
func _sleepy() -> bool:
	if surface == null or surface.pilot == null or not ("sleepers" in surface):
		return false
	if position.distance_squared_to(surface.pilot.position) > FAR * FAR:
		return true
	return _state != "chase" and _state != "bite" and surface.view_rect.has_area() \
			and not surface.view_rect.has_point(position)


## A sleeper's turn: it thinks with the time it slept; back in view (or
## fighting) it wakes. False once awake.
func sleep_tick(now: float) -> bool:
	if dead or not asleep:
		asleep = false
		return false
	var far := surface.pilot != null and position.distance_squared_to(surface.pilot.position) > FAR * FAR
	_far_skip = far and not _far_skip
	if _far_skip:
		return true   # (far: every other turn)
	var dt := clampf(now - _slept_at, 0.0, 0.5)
	_slept_at = now
	_think(dt)
	if dead or not _sleepy():
		wake()
		return false
	return true


## Back to thinking every frame (hit, or in view again).
func wake() -> void:
	if asleep:
		asleep = false
		set_process(not dead)


func _think(delta: float) -> void:
	_t += delta
	_hurt = move_toward(_hurt, 0.0, delta * 3.0)
	_grudge = maxf(0.0, _grudge - delta)
	_cd = maxf(0.0, _cd - delta)
	if _state == "chase" or _state == "bite":   # (any that fights: predators, and grazers turned on you)
		_fight(delta)
		_redraw()
		return
	match spec["temper"]:
		"predator":
			_predator(delta)
		"bird":
			_bird(delta)
		"soar":
			_soar(delta)
		"drift":
			_clock += delta
			_wander(delta)
			_pose = floori(_clock * 2.5) % 4   # (a pulse: all four poses in turn)
			_alt = spec["alt"] + sin(_clock * 1.7) * 6.0
		_:
			_beast(delta)
	_redraw()


## Redrawn only while in view (or near it): _draw runs for whatever asks,
## seen or not - a hundred animals a frame, most of them off screen.
func _redraw() -> void:
	if surface == null or not (surface.get("view_rect") is Rect2) or not surface.view_rect.has_area() \
			or surface.view_rect.has_point(position):
		queue_redraw()


# --- On the ground ------------------------------------------------------------------

## Grazers, skittish ones and the tortoise.
func _beast(delta: float) -> void:
	var shy: float = spec["shy"]
	_look -= delta
	if _look <= 0.0 and shy > 0.0 and _state != "flee":
		_look = 0.25
		var you := _you_near(shy)
		if you:
			if spec["temper"] == "slow":
				_go("hide")
			else:
				_flee(you)
	match _state:
		"flee":
			_pose_walk()
			var gone: bool = not is_instance_valid(_threat)
			if gone or position.distance_to(_threat.position) > maxf(shy, 200.0) * 2.2 or _t > 6.0:
				home = position   # (settles where it ran to)
				_idle()
			elif not _run_from(_threat, delta):
				if _t > 1.0:
					_idle()
		"hide":   # (the tortoise, in its shell)
			_pose = 3
			if _you_near(shy * 1.3) == null and _t > 2.0:
				_idle()
			elif _you_near(shy * 1.3) != null:
				_t = minf(_t, 0.5)
		_:
			_wander(delta)


## Strolling about home: idle, walk to a spot, or its special pose a while.
func _wander(delta: float) -> void:
	match _state:
		"walk":
			_pose_walk()
			if position.distance_to(_goal) < 6.0 or _t > 12.0 \
					or not _go_toward(_goal, spec["walk"], delta) or _stuck(delta, spec["walk"]):
				_idle()
		"act":
			_pose = 3
			if _t > _wait:
				_idle()
		_:
			_pose = 0
			_wait -= delta
			if _wait <= 0.0:
				if randf() < 0.35 and not spec.get("coiled", false):
					_wait = randf_range(2.0, 5.0)
					_go("act")
				else:
					_goal = _open_spot()
					_go("walk")


# --- Getting about (round corners, not into them) ------------------------------------

var _route := PackedVector2Array()   # waypoints round what's in the way (the surface's path grid)
var _route_to := Vector2.INF
var _route_t := 0.0
var _clear_t := 0.0
var _clear_to := Vector2.INF        # (where the clear-way check was for)
var _clear := true                   # the straight way to where it's going is open (checked now and then)
var _stuck_at := Vector2.INF
var _stuck_for := 0.0
var _flee_dir := Vector2.ZERO
var _flee_t := 0.0

## A step toward `target`: straight when the way is open, else along a route
## round the obstacle (re-planned as the target moves). False if it can't move.
func _go_toward(target: Vector2, speed: float, delta: float) -> bool:
	if surface == null:
		return false
	_clear_t -= delta
	if _clear_t <= 0.0 or _clear_to.distance_to(target) > 60.0:
		_clear_to = target   # (its own: _route_to is only set when routing - a clear way was re-checked every frame)
		# (the straight way re-checked each second - 4 times a second chasing or fleeing)
		_clear_t = 0.25 if _state == "chase" or _state == "bite" or _state == "flee" else 1.0
		_clear = not surface.has_method("_segment_clear") or surface._segment_clear(position, target, 6.0, 8.0)
	if _clear:
		_route = PackedVector2Array()
		return _step(position.direction_to(target), speed, delta)
	_route_t -= delta
	if (_route.is_empty() or _route_to.distance_to(target) > 60.0) and _route_t <= 0.0 \
			and surface.creature_paths < surface.CREATURE_PATHS:   # (a few searches a frame between all the animals)
		surface.creature_paths += 1
		_route_t = 0.8
		_route_to = target
		# (no partial routes: a target in another region of the grid is refused at once)
		_route = surface.find_path(position, target, false) if surface.in_nav(position, 2) and surface.in_nav(target, 2) else PackedVector2Array()
	while not _route.is_empty() and position.distance_to(_route[0]) < 8.0:
		_route.remove_at(0)
	var to: Vector2 = _route[0] if not _route.is_empty() else target
	return _step(position.direction_to(to), speed, delta)


## No headway for `limit` s while trying to move at `speed` (stuck in a corner).
func _stuck(delta: float, speed: float, limit := 1.5) -> bool:
	if _stuck_at == Vector2.INF or position.distance_to(_stuck_at) > maxf(10.0, speed * 0.25):
		_stuck_at = position
		_stuck_for = 0.0
		return false
	_stuck_for += delta
	if _stuck_for > limit:
		_stuck_at = Vector2.INF
		return true
	return false


## Somewhere to stroll to: a spot near home it can walk to in a straight line
## (a few tries), else back toward home.
func _open_spot() -> Vector2:
	_stuck_at = Vector2.INF
	for k in 8:
		var g := home + Vector2(randf_range(-WANDER, WANDER), randf_range(-WANDER, WANDER) * 0.5)
		if surface == null or (surface.walkable_at(g) and (not surface.has_method("_segment_clear") or surface._segment_clear(position, g, 6.0, 8.0))):
			return g
	# Hemmed in (a corner): whichever way round it is open, the one nearest home first.
	var best := home
	var best_d := INF
	for k in 12:
		var g := position + Vector2.from_angle(k * TAU / 12.0) * Vector2(100.0, 50.0)
		if surface.walkable_at(g) and surface._segment_clear(position, g, 6.0, 8.0):
			var d := g.distance_to(home)
			if d < best_d:
				best_d = d
				best = g
	return best


## Running from `threat`: the open way (of 12 round it) that takes it furthest
## from it - re-chosen now and then, so it runs round walls, not into them.
func _run_from(threat: Node2D, delta: float) -> bool:
	_flee_t -= delta
	if _flee_t <= 0.0 or _flee_dir == Vector2.ZERO:
		_flee_t = 0.5
		var away := threat.position.direction_to(position)
		var best := -INF
		for k in 12:
			var d := Vector2.from_angle(k * TAU / 12.0)
			var probe := position + d * 120.0
			if surface and not (surface.walkable_at(probe) and (not surface.has_method("_segment_clear") or surface._segment_clear(position, probe, 6.0, 8.0))):
				continue
			var score := d.dot(away) + 0.0001 * probe.distance_to(threat.position)
			if score > best:
				best = score
				_flee_dir = d
		if best == -INF:
			_flee_dir = away
	return _step(_flee_dir, spec["run"], delta)


func _idle() -> void:
	_wait = randf_range(1.5, 6.0)
	_go("idle")


func _flee(from: Node2D) -> void:
	_threat = from
	if _state != "flee":
		_go("flee")


func _pose_walk() -> void:
	_pose = 1 + (floori(_phase / PI) & 1)


## One step toward dir (or as near it as the ground allows); true if it moved.
func _step(dir: Vector2, speed: float, delta: float) -> bool:
	if surface == null or dir == Vector2.ZERO:
		return false
	for turn in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6]:
		var step: Vector2 = dir.rotated(turn) * speed * delta
		if surface.walkable_at(position + step):
			position += step
			_phase += step.length() / STRIDE * TAU
			if absf(step.x) > 0.01:
				_right = step.x > 0.0
			return true
	return false


# --- Predators ------------------------------------------------------------------------

func _predator(delta: float) -> void:
	var sense: float = spec["sense"]
	_hunger -= delta
	match _state:
		"flee":
			_pose_walk()
			if not is_instance_valid(_threat) or position.distance_to(_threat.position) > 900.0 or _t > 8.0:
				home = position
				_threat = null
				_idle()
			else:
				_run_from(_threat, delta)
		_:
			_look -= delta
			if _look <= 0.0:
				_look = 0.3
				var you := _you_near(sense)
				if you and SurfaceProps.clear_shot(self, position, you.position):
					_hunt(you)
					_call_pack(you)
					return
				if _hunger <= 0.0:
					var meal := _find_prey(sense)
					if meal:
						_hunt(meal)
						_call_pack(meal)
						meal.spotted(self)
						return
					_hunger = 3.0   # (nothing near: look again soon)
			_wander(delta)


## Going for its prey (you, another animal, or whoever hurt it): closes in on
## its own side of it and bites in reach. A predator that brings down an
## animal stops to feed, and won't hunt again for a while.
func _fight(delta: float) -> void:
	var sense: float = spec.get("sense", 320.0)
	var prey := _threat
	if not _prey_ok(prey) or position.distance_to(prey.position) > sense * 2.2 and _grudge <= 0.0:
		var fed: bool = is_instance_valid(prey) and prey.get("dead") == true and prey != _you()
		_threat = null
		if fed:
			_hunger = randf_range(40.0, 90.0)
			_wait = 3.0
			_go("act")   # (feeding)
		else:
			_goal = home
			_go("walk")   # (back home)
		return
	if hp < max_hp * FLEE_HP and (spec.get("flees", false) or not hostile):
		_flee(prey)
		return
	var d := position.distance_to(prey.position)
	if _state == "bite":
		_pose = 3
		if _t > 0.35:
			_go("chase")
		return
	# (each to its own side of it: a pack closes in from around)
	var spot: Vector2 = prey.position + _side * _reach() * 0.8
	if surface and not surface.walkable_at(spot):
		spot = prey.position   # (its side is blocked: straight at it)
	_keep_apart(delta)
	# In reach: it bites - wherever it stands (its own side of the prey is only
	# how it closes in; one it can't get to mustn't keep it from biting).
	if d <= _reach():
		_pose = 3 if spec.get("charge", false) else 0
		_right = prey.position.x > position.x
		if _cd <= 0.0:
			_cd = spec.get("every", 1.2)
			_go("bite")
			if surface and prey == surface.get("pilot"):
				surface.bitten_by = spec["name"]
				surface.bitten_at = Time.get_ticks_msec()
				surface.bitten_by_node = self
			elif prey.has_method("attacked_by"):
				prey.attacked_by(self)   # (it runs, hides or fights back)
			prey.surface_hit(_bite(), "heat" if set_id == "vo" else "kinetic")   # (the volcanic beasts burn)
		return
	if position.distance_to(spot) < 4.0:
		_pose = 0
		return
	if _stuck(delta, spec["run"], 4.0):
		_threat = null   # (no way to it: back home)
		_goal = home
		_go("walk")
		return
	if _go_toward(spot, minf(spec["run"], position.distance_to(spot) / delta), delta):
		if spec.get("charge", false):
			_pose = 3 if floori(_phase / PI) & 1 else 1   # (charging)
		else:
			_pose_walk()
	elif spot != prey.position and _go_toward(prey.position, minf(spec["run"], d / delta), delta):
		_pose_walk()   # (its side blocked: straight at it)
	else:
		_pose = 0   # (no step this frame: standing, not frozen mid-lunge)


## Its bite: a predator's or fighter's own; any other animal defending its
## group bites by its size.
func _bite() -> float:
	return spec.get("bite", maxf(3.0, max_hp / 8.0))


func _reach() -> float:
	return spec.get("reach", maxf(40.0, spec["h"] * 0.6))


## A hungry predator's next meal: the nearest animal in sense that isn't of
## its kind, is on the ground and no bigger than it - or null.
func _find_prey(sense: float) -> Node2D:
	var best: Node2D = null
	var best_d := sense
	for c in get_tree().get_nodes_in_group("surface_creatures"):
		if c == self or c.species == species or c.dead or c.flying() or c.max_hp > max_hp:
			continue
		var d: float = position.distance_to(c.position)
		if d < best_d:
			best = c
			best_d = d
	return best


## Not on top of its packmates: a step away from any too close.
func _keep_apart(delta: float) -> void:
	var push := Vector2.ZERO
	for c in get_tree().get_nodes_in_group("surface_creatures"):
		if c != self and c.hostile:
			var off: Vector2 = position - c.position
			var d := off.length()
			if d < 34.0:
				push += (off / d if d > 0.1 else Vector2.from_angle(randf() * TAU)) * (34.0 - d)
	if push != Vector2.ZERO and surface:
		var step := push.limit_length(70.0 * delta)
		if surface.walkable_at(position + step):
			position += step


func _prey_ok(p: Variant) -> bool:
	if not is_instance_valid(p) or p.get("dead") == true:
		return false
	if surface and p == surface.get("pilot"):
		return surface.pilot_targetable()
	return true


func _hunt(prey: Node2D) -> void:
	_threat = prey
	if _state != "chase" and _state != "bite":
		_go("chase")


## A wolf that finds you howls its pack along.
func _call_pack(prey: Node2D) -> void:
	if not spec.get("pack", false):
		return
	for c in get_tree().get_nodes_in_group("surface_creatures"):
		if c != self and c.species == species and not c.dead and c.position.distance_to(position) < 500.0:
			c._hunt(prey)


# --- Birds ------------------------------------------------------------------------------

## The owl: perched; off when you come near (or after a while), to a perch further on.
func _bird(delta: float) -> void:
	match _state:
		"fly":
			_pose = 1 + (floori(_t * 8.0) & 1)
			var to := _goal - position
			var d := to.length()
			var step := minf(d, spec["run"] * delta)
			if d > 0.5:
				position += to / d * step
				_right = to.x > 0.0
			_alt = move_toward(_alt, minf(70.0, d * 0.4), 120.0 * delta)
			if d < 2.0 and _alt < 1.0:
				home = position
				_go("perch")
				_wait = randf_range(15.0, 40.0)
		_:
			_pose = 3 if fmod(_t, 7.0) > 5.0 else 0   # (now and then it turns its head)
			_alt = 0.0
			_wait -= delta
			_look -= delta
			if _look <= 0.0:
				_look = 0.3
				if _you_near(spec["shy"]) or _wait <= 0.0:
					_take_off(randf_range(350.0, 600.0))


func _take_off(dist: float) -> void:
	for k in 12:
		var g := position + Vector2.from_angle(randf() * TAU) * dist * Vector2(1.0, 0.6)
		if surface and surface.walkable_at(g):
			_goal = g
			_go("fly")
			return
	_wait = 5.0


## The eagle: circles over its home; now and then it lands a while.
func _soar(delta: float) -> void:
	match _state:
		"soar":
			_pose = 1 + (floori(_t * 1.6) & 1)
			_ang += delta * spec["run"] / _circle()
			var p := home + Vector2(cos(_ang), sin(_ang) * 0.5) * _circle()
			_right = p.x > position.x
			position = p
			_alt = move_toward(_alt, _soar_alt(), 60.0 * delta)
			if spec.get("lands", true) and _t > 25.0 and randf() < delta / 15.0:
				var g := position + Vector2(randf_range(-150, 150), randf_range(-80, 80))
				if surface and surface.walkable_at(g) and _you_near(spec["shy"] * 2.0) == null:
					_goal = g
					_go("dive")
		"dive":
			_pose = 3
			position = position.move_toward(_goal, spec["run"] * delta)
			_alt = move_toward(_alt, 0.0, 110.0 * delta)
			if _alt <= 0.0 and position.distance_to(_goal) < 2.0:
				_go("perch")
				_wait = randf_range(6.0, 14.0)
		"perch":
			_pose = 0
			_wait -= delta
			if _wait <= 0.0 or _you_near(spec["shy"]):
				home = position - Vector2(cos(_ang), sin(_ang) * 0.5) * _circle()
				_go("climb")
		"climb":
			_pose = 1 + (floori(_t * 4.0) & 1)
			_alt = move_toward(_alt, _soar_alt(), 70.0 * delta)
			_ang += delta * spec["run"] / _circle()
			position = position.move_toward(home + Vector2(cos(_ang), sin(_ang) * 0.5) * _circle(), spec["run"] * delta)
			if _alt >= _soar_alt():
				_go("soar")


func _circle() -> float:
	return spec.get("circle", SOAR_R)


func _soar_alt() -> float:
	return spec.get("alt", SOAR_ALT)


func flying() -> bool:
	return _alt > 1.0


# --- Hits ------------------------------------------------------------------------------

func surface_hit(d: float, _dtype := "") -> void:
	wake()
	if dead:
		return
	hp -= d
	_hurt = 1.0
	if hp <= 0.0:
		_die()


## Hurt by someone (shot, bitten): a predator - or a grazer that fights -
## goes for them (its pack too); the rest run, or hide in their shells. One of
## a group (its kind within GROUP_R) hurt: the whole group turns on them.
const GROUP_R := 450.0

func attacked_by(who: Node2D) -> void:
	if dead or not is_instance_valid(who) or who == self:
		return
	last_by = who
	if _ground_animal() and who.get("species") != species:
		var group := _group()
		if not group.is_empty():
			for c in group + [self]:
				c._defend(who)
			return
	if hostile or spec.get("fights", false):
		_grudge = GRUDGE
		if not (hp < max_hp * FLEE_HP and (spec.get("flees", false) or not hostile)):
			if _threat != who or (_state != "chase" and _state != "bite"):
				_threat = null
			_hunt(who)
			_call_pack(who)
		return
	spotted(who)


## On the ground (not a bird, a flier or a drifter): it can fight in a group.
func _ground_animal() -> bool:
	return not spec["temper"] in ["bird", "soar", "drift"]


## The others of its kind near it (alive, on the ground).
func _group() -> Array:
	var out := []
	for c in get_tree().get_nodes_in_group("surface_creatures"):
		if c != self and c.species == species and not c.dead and c.position.distance_to(position) < GROUP_R:
			out.append(c)
	return out


## Its group was attacked by `who`: it goes for them too (unless badly hurt:
## it runs).
func _defend(who: Node2D) -> void:
	if dead or not is_instance_valid(who):
		return
	_grudge = GRUDGE
	if hp < max_hp * FLEE_HP:
		_flee(who)
		return
	if _threat != who:
		_threat = null
	_hunt(who)


## Something is coming for it: runs (the shy and skittish, and tame grazers),
## or hides (the slow ones). Fighters and predators wait to be hurt.
func spotted(by: Node2D) -> void:
	if dead or hostile or spec.get("fights", false):
		return
	match spec["temper"]:
		"grazer", "skittish":
			_flee(by)
		"slow":
			_go("hide")
		"bird":
			if _state != "fly":
				_take_off(randf_range(350.0, 600.0))


func _die() -> void:
	dead = true
	remove_from_group("surface_hostiles")
	remove_from_group("surface_creatures")
	if surface and surface.has_method("creature_died"):
		surface.creature_died(self)
	var tw := create_tween()
	tw.tween_property(self, "_alt", 0.0, 0.3)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 1.2).set_delay(0.5)
	tw.tween_callback(queue_free)


func click_center() -> Vector2:
	return global_position + Vector2(0, -_alt - height * 0.5)


func interact(_surface: Node) -> void:
	if _surface and _surface.has_method("show_prompt"):
		_surface.show_prompt("A %s." % spec["name"], 2.0)
	if spec["temper"] in ["grazer"] and spec["shy"] == 0.0:
		_wait = 2.5
		_go("act")   # (the sheep grazes on, the donkey brays)


# --- Drawing -------------------------------------------------------------------------

func _draw() -> void:
	var tex: Texture2D = _tex[_pose] if _pose < _tex.size() else null
	var w: float = spec["h"] * 0.55 if not spec.get("coiled", false) else spec["h"] * 1.1
	SurfaceProps.shadow(self, w, w * 0.32, 0.25 * clampf(1.0 - _alt / 260.0, 0.25, 1.0))
	z_index = 12 if _alt > 80.0 else 0   # (high in the air: over the scenery)
	if tex == null:
		draw_circle(Vector2(0, -_alt - 12), 12, Color(0.6, 0.45, 0.3))
		return
	var sz := tex.get_size() * _k
	var tint := Color.WHITE.lerp(Color(1.0, 0.35, 0.3), _hurt * 0.7)
	draw_set_transform(Vector2(0, -_alt), 0.0, Vector2(-1.0 if _right else 1.0, 1.0))
	draw_texture_rect(tex, Rect2(-sz.x * 0.5, -sz.y, sz.x, sz.y), false, tint)
	draw_set_transform(Vector2.ZERO)
	if hp < max_hp:   # a health bar once hurt
		var bw := 44.0
		var r := Rect2(-bw / 2.0, -_alt - spec["h"] - 14.0, bw, 5)
		draw_rect(r.grow(1), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(r.position, Vector2(bw * clampf(hp / max_hp, 0.0, 1.0), 5)), Color(1.0, 0.3, 0.25))
