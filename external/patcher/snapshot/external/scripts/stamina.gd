class_name Stamina
extends RefCounted
## The automaton's stamina on foot (the green ring outside its shield ring on
## the surface's health gauge): it runs down as you walk the world - DRAIN a
## second, COMBAT times faster in a fight (hit lately, or firing) - and comes
## back when you eat: any Food & drink good you carry (FOOD each) or an
## Energy Drink (DRINK). Empty, you walk at TIRED_SPEED and your health no
## longer comes back by itself. Kept with the player ("stamina": PlayerData),
## so it carries over from one landing to the next.

const MAX := 100.0
const DRAIN := MAX / 600.0      # a full ring lasts 10 calm minutes
const COMBAT := 3.0             # x faster while fighting
const LOW := 20.0               # the ring's rim turns red below it
const FOOD := 30.0              # a Food & drink good
const DRINK := 60.0             # an Energy Drink
const DRINK_ID := "energy_drink"
const TIRED_SPEED := 0.6
const COOLDOWN := 1.5           # s between two meals


## How much stamina eating / drinking `id` gives back (0: not food).
static func restores(id: String) -> float:
	if id == DRINK_ID:
		return DRINK
	return FOOD if is_food(id) else 0.0


static func is_food(id: String) -> bool:
	return id in TradeGoods.CATEGORIES[0][1]


## The player's stamina (a save's player dictionary; full if never set).
static func of(player: Dictionary) -> float:
	return clampf(float(player.get("stamina", MAX)), 0.0, MAX)
