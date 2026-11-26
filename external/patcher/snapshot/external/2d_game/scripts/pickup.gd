class_name Pickup
extends Node2D
## Loot floating in space. Drifts to a stop, is pulled toward the player when
## close, and is added to the player's inventory on contact. Despawns after
## a while (blinking at the end).

const MAGNET_RANGE := 260.0
const COLLECT_RANGE := 40.0
const LIFETIME := 60.0

var item_id := "scrap"
var amount := 1
var velocity := Vector2.ZERO
var _time := 0.0
## Quest relics never despawn.
var permanent := false
## False = visible but can't be picked up yet (e.g. while it's guarded).
var collectible := true
## Cut by the player's mining beam: pulled to the ship from any distance.
var tractor := false


static func spawn(tree: SceneTree, at: Vector2, id: String, n: int) -> Pickup:
	var p := Pickup.new()
	p.add_to_group("pickups")
	p.item_id = id
	p.amount = n
	p.velocity = Vector2.from_angle(randf() * TAU) * randf_range(60, 200)
	var layer := tree.get_first_node_in_group("fx_layer")
	layer.add_child(p)
	p.global_position = at
	return p


func _process(delta: float) -> void:
	_time += delta
	if _time > LIFETIME and not permanent:
		queue_free()
		return

	velocity = velocity.move_toward(Vector2.ZERO, 120.0 * delta)
	var ship := get_tree().get_first_node_in_group("player") as Node2D
	if ship and ship.is_alive():
		var to_ship := ship.global_position - global_position
		var d := to_ship.length()
		if not collectible or not fits():
			if collectible and d < COLLECT_RANGE * 3.0:
				_hold_full_notice(ship)
			pass   # (cargo with no room in the hold: it stays out here, for later)
		elif d < COLLECT_RANGE:
			_collect()
			return
		var data := get_tree().get_first_node_in_group("player_data")
		var magnet: float = MAGNET_RANGE * (1.0 + (data.mod("magnet_mult") if data else 0.0))
		if collectible and (d < magnet or tractor):
			velocity = velocity.move_toward(to_ship.normalized() * 600.0, 1500.0 * delta)
	global_position += velocity * delta
	if UI.redraw_due(self):   # (its spin and glow; it moves with its node every frame)
		queue_redraw()


## Room for it in the hold (Inventory slots: everything takes room).
func fits() -> bool:
	if item_id == "credits":
		return true
	var data := get_tree().get_first_node_in_group("player_data")
	return data == null or data.room_for(item_id) >= amount


static var _notice_t := 0

static func _hold_full_notice(ship: Node) -> void:
	if Time.get_ticks_msec() - _notice_t > 4000:
		_notice_t = Time.get_ticks_msec()
		ship.message.emit("Cargo hold full - sell or drop something to pick this up")


func _collect() -> void:
	var data := get_tree().get_first_node_in_group("player_data")
	if data:
		data.add_item(item_id, amount)
	Scenarios.event("picked", {"item": item_id})
	GameLog.loot(Items.display_name(item_id), amount)
	var color := UI.GOLD if item_id == "credits" else Color(0.7, 0.95, 1.0)
	Effects.float_text(global_position + Vector2(0, -20), "+%d %s" % [amount, Items.display_name(item_id)], color)
	Sfx.play("space/credits" if item_id == "credits" else "space/pickup")
	queue_free()


func _draw() -> void:
	# Blink during the last 10 seconds.
	if not permanent and _time > LIFETIME - 10.0 and fmod(_time, 0.4) < 0.15:
		return
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	var glow := UI.GOLD if item_id == "credits" else Color(0.5, 0.9, 1.0)
	draw_circle(Vector2.ZERO, 22.0 + 4.0 * pulse, Color(glow, 0.12))
	draw_arc(Vector2.ZERO, 18.0, 0, TAU, 24, Color(glow, 0.4 + 0.3 * pulse), 1.5, true)
	var bob := Vector2(0, sin(_time * 2.5) * 2.0)
	Items.draw_icon(self, item_id, Rect2(Vector2(-13, -13) + bob, Vector2(26, 26)))
