class_name MonsterPursuit
extends Node
## A monster-signal creature on your trail (SignalSite.leave): you left its
## site while it lived and hunted you, so after FOLLOW_DELAY s it comes out of
## the void after you, into the system - as hurt as you left it - hunting you
## at your ship's speed and attacking any NPC ship in its path (Enemy.hunting).
## Kill it there and it drops the signal's loot; the signal is done. Going back
## into its signal brings it back to its site (SignalSite._build_monster); in
## another site it waits, and follows you out again. Jumping to another system
## loses it (the beacon stays). It isn't saved (Main.get_save_data).

const FOLLOW_DELAY := 5.0
const SURFACE := 1300.0             # this far from you it comes out

var main: Node
var monster: Node2D
var sig: Dictionary = {}
var creature: Array = []            # its SignalSite.CREATURES entry
var _wait := FOLLOW_DELAY
var _out := false                   # in the system, hunting
var _warned := false


static func start(m: Node, mon: Node2D, signal_data: Dictionary, entry: Array) -> MonsterPursuit:
	var p := MonsterPursuit.new()
	p.main = m
	p.monster = mon
	p.sig = signal_data
	p.creature = entry
	p.name = "MonsterPursuit"
	mon.set_meta("pursuit", true)
	mon.died.connect(p._on_died)
	m.add_child(p)
	p._stash()
	return p


## Out of the world while it waits (frozen, hidden where it was).
func _stash() -> void:
	_out = false
	_wait = FOLLOW_DELAY
	_warned = false
	if is_instance_valid(monster):
		monster.visible = false
		monster.process_mode = Node.PROCESS_MODE_DISABLED
		monster.velocity = Vector2.ZERO
		var mon = monster.body.get_node_or_null("Monster")
		if mon:
			mon.calm()


func _process(delta: float) -> void:
	if not is_instance_valid(monster):
		queue_free()   # (gone with the system: you jumped away)
		return
	if main.site != null:
		if _out:
			_stash()   # (you went into another signal: it waits for you)
		return
	if _out:
		return
	_wait -= delta
	if not _warned and _wait < FOLLOW_DELAY - 1.5:
		_warned = true
		GameLog.post("Something followed you out of the signal...", "combat")
		Sfx.play("space/monster_roar", -10.0)
	if _wait <= 0.0:
		_surface()


func _surface() -> void:
	var ship: Node2D = main.ship
	if not ship.is_alive():
		return
	_out = true
	var dir := Vector2.from_angle(randf() * TAU)
	monster.global_position = ship.global_position + dir * SURFACE
	monster.home = monster.global_position
	monster.velocity = Vector2.ZERO
	monster.hunting = true
	monster._target = ship
	monster.visible = true
	monster.modulate.a = 0.0
	monster.process_mode = Node.PROCESS_MODE_INHERIT
	monster.create_tween().tween_property(monster, "modulate:a", 1.0, 1.2)
	Sfx.play_world("space/monster_roar", monster.global_position, 0.0, 0.2)
	main.hud.flash_message("%s has followed you out of the signal!" % creature[1])
	GameLog.post("%s has followed you out of the signal - it's hunting you." % creature[1], "combat")


## Gone back into its signal: the site takes it back.
func give_back() -> Node2D:
	var m := monster
	monster = null
	if is_instance_valid(m):
		m.died.disconnect(_on_died)
		m.remove_meta("pursuit")
		m.visible = true
		m.modulate.a = 1.0
		m.process_mode = Node.PROCESS_MODE_INHERIT
	queue_free()
	return m


## Killed out here: the signal's loot where it died, the signal done.
func _on_died(_m: Node2D) -> void:
	var at: Vector2 = _m.global_position
	for d in [["alien_alloy", randi_range(3, 5), Vector2.ZERO], ["data_core", randi_range(1, 2), Vector2(40, 0)], ["credits", randi_range(500, 900), Vector2(-40, 20)]]:
		var p := Pickup.spawn(get_tree(), at + d[2], d[0], maxi(1, roundi(d[1] * SignalSites.mult(sig))))
		p.permanent = true
		p.velocity *= 0.15
	sig["done"] = true
	GameLog.post("Signal source: %s is dead - collect what it left." % creature[1], "good")
	Sfx.play("space/scan_done")
	main.refresh_beacons()
	queue_free()
