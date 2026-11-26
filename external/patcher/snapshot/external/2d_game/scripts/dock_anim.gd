class_name DockAnim
## Docking / landing animation: the ship turns toward the station or planet,
## glides to its centre and slowly shrinks until it's gone (into). The reverse
## (out_of) grows it out of the centre and glides it back out. No fading: the
## ship stays solid, it just gets smaller.
##
## `node` is moved; `visual` is shrunk and faded (the node itself for AI
## ships, the sprite for the player's ship - its camera must not scale);
## `turn` is what faces the way it glides (the node, or an AI ship's body).

const SHRINK_TIME := 1.3
const GROW_TIME := 1.1


## Seconds to glide a distance (quick for short hops, never sluggish).
static func glide_time(dist: float) -> float:
	return clampf(dist / 520.0, 0.45, 1.6)


static func into(node: Node2D, visual: CanvasItem, target: Vector2, done := Callable(), turn: Node2D = null) -> Tween:
	turn = node if turn == null else turn
	var from := node.global_position
	var t := node.create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if from.distance_to(target) > 4.0:
		var face := (target - from).angle() + PI / 2.0   # sprites point up (-y)
		var cur := turn.global_rotation
		t.tween_property(turn, "global_rotation", cur + wrapf(face - cur, -PI, PI), 0.25).set_trans(Tween.TRANS_SINE)
		t.tween_property(node, "global_position", target, glide_time(from.distance_to(target))) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var base: Vector2 = visual.scale
	t.tween_property(visual, "scale", base * 0.01, SHRINK_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func(): visual.visible = false)
	if done.is_valid():
		t.tween_callback(done)
	return t


## The reverse: appears at `from` (the centre), grows, then glides to `to`.
static func out_of(node: Node2D, visual: CanvasItem, from: Vector2, to: Vector2, base_scale: Vector2, done := Callable(), turn: Node2D = null) -> Tween:
	turn = node if turn == null else turn
	node.global_position = from
	visual.scale = base_scale * 0.01
	visual.visible = true
	var t := node.create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(visual, "scale", base_scale, GROW_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if from.distance_to(to) > 4.0:
		turn.global_rotation = (to - from).angle() + PI / 2.0
		t.tween_property(node, "global_position", to, glide_time(from.distance_to(to))) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if done.is_valid():
		t.tween_callback(done)
	return t
