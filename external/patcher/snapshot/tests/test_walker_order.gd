extends TestCase
## Aboard a moving ship you're drawn where the ship is now: the walker moves
## after the ships each frame (its deck already where it is this frame) and
## before the camera that follows it. (A ship made after the walker - a hired
## ride, a trader come into port - moved after it in the tree's order: the
## walker was drawn a frame behind, outside the hull, at a climb's speed metres off.)


func test_walker_after_ships_before_camera() -> void:
	var W: GDScript = load("res://scripts/world/player/cosmos_walker.gd")
	var w: Node3D = W.new()
	tree.root.add_child(w)
	var ship_prio := 0   # (CosmosNpcShip, CosmosShip: the default)
	check(w.process_priority > ship_prio, "the walker after the ships (%d)" % w.process_priority)
	check(w.process_priority < 10, "and before the camera (10)")
	w.queue_free()
	await tree.process_frame
