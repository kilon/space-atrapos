extends TestCase
## The memory pool (AssetPool): loaded assets stay loaded; over budget the
## least used that nothing holds are unloaded (pinned ones never), each unload
## noted; the budget twice the usual need; ProcArt's sprites in it; the
## loading console shows its notes and the pool's total.

var _saved := []


func _swap_in() -> void:
	_saved = [AssetPool._e, AssetPool.used, AssetPool.budget, AssetPool.need, AssetPool.events, AssetPool.serial, AssetPool.unloads, AssetPool.unloaded_bytes, AssetPool.loads, AssetPool.peak]
	AssetPool._e = {}
	AssetPool.events = []
	AssetPool.used = 0
	AssetPool.unloads = 0
	AssetPool.unloaded_bytes = 0


func _swap_out() -> void:
	AssetPool._e = _saved[0]
	AssetPool.used = _saved[1]
	AssetPool.budget = _saved[2]
	AssetPool.need = _saved[3]
	AssetPool.events = _saved[4]
	AssetPool.serial = _saved[5]
	AssetPool.unloads = _saved[6]
	AssetPool.unloaded_bytes = _saved[7]
	AssetPool.loads = _saved[8]
	AssetPool.peak = _saved[9]


func test_unloads_least_used_only_when_full() -> void:
	_swap_in()
	AssetPool.set_need(150)
	check(AssetPool.budget == 300, "the room is twice the usual need")
	var gone := []
	var held := {"busy": true}
	AssetPool.add("rare", 100, func(): gone.append("rare"))
	AssetPool.add("common", 100, func(): gone.append("common"))
	AssetPool.add("busy", 100, func(): gone.append("busy"), func(): return held["busy"])
	for i in 5:
		AssetPool.touch("common")
		AssetPool.touch("busy")
	check(gone.is_empty() and AssetPool.used == 300, "nothing unloaded while it fits (%d bytes)" % AssetPool.used)
	check(AssetPool.priority("common") > AssetPool.priority("rare"), "used more, a higher priority")
	AssetPool.add("pinned", 100, func(): gone.append("pinned"), Callable(), true)
	check(gone == ["rare"], "over budget: the least used goes first (%s)" % [gone])
	check(AssetPool.used == 300 and not AssetPool.has("rare"), "and the pool fits again")
	AssetPool.add("more", 100, func(): gone.append("more"))
	check(not "busy" in gone and not "pinned" in gone, "never one that's held, nor a pinned one (%s)" % [gone])
	check(AssetPool.unloads == 2, "unloads counted (%d)" % AssetPool.unloads)
	var notes: Array = AssetPool.events.filter(func(e): return e[2] == "unload")
	check(notes.size() == 2 and str(notes[0][1]).begins_with("Unloaded rare"), "each unload reported (%s)" % [notes])
	check(AssetPool.summary().contains("2 unloaded"), "the total reports them: " + AssetPool.summary())
	_swap_out()


func test_sprites_are_in_the_pool() -> void:
	ProcArt.get_tex("ship_player")
	check(AssetPool.has("ship_player"), "a loaded sprite is in the pool")
	check(AssetPool.budget >= 2 * 200 * 1048576, "room for twice every sprite (%s)" % AssetPool.mb(AssetPool.budget))
	check(AssetPool.used > 0 and AssetPool.used <= AssetPool.budget, "its total counted: " + AssetPool.summary())
	var p := AssetPool.priority("ship_player")
	ProcArt.sprite("ship_player")
	check(AssetPool.priority("ship_player") > p, "drawing a sprite raises its priority")
