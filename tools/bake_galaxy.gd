extends SceneTree
## Bakes the grown galaxy (Galaxy.grow_fresh: ~0.5 s of searching) into
## data/galaxy.json, which the game reads at its start (Galaxy._grow). Run it
## after changing anything the galaxy grows from (Galaxy.layout_key):
##   godot --headless --path . -s tools/bake_galaxy.gd


func _initialize() -> void:
	var g: GDScript = load("res://scripts/sim/galaxy.gd")
	var t := Time.get_ticks_msec()
	var grown: Array = g.grow_fresh()
	var f := FileAccess.open(g.LAYOUT_FILE, FileAccess.WRITE)
	f.store_string(g.layout_json(grown))
	f.close()
	print("Galaxy baked: %d systems, %d lanes (%d ms) -> %s" % [grown[0].size(), grown[1].size(), Time.get_ticks_msec() - t, g.LAYOUT_FILE])
	quit()
