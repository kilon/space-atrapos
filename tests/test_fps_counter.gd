extends TestCase
## The FPS counter (FpsCounter): one over every scene, shown while the
## setting is on (the default), hidden when it's off, and the setting saved.

func _counter() -> FpsCounter:
	for n in tree.root.get_children():
		if n is FpsCounter:
			return n
	return null


func test_fps_counter() -> void:
	var saved: bool = Settings.fps_counter
	var c := _counter()
	check(c != null, "an FPS counter is over the game")
	check(Settings.fps_counter_default(), "it's on by default when run from the project")
	check(not OS.has_feature("template"), "(this isn't an exported build - where it's off by default)")
	Settings.set_fps_counter(true)
	await tree.process_frame
	await tree.process_frame
	check(c.visible and c.label.text.contains("FPS"), "shown with a reading while on (%s)" % c.label.text)
	Settings.set_fps_counter(false)
	await tree.process_frame
	await tree.process_frame
	check(not c.visible, "hidden when switched off")
	Settings.save_settings()
	Settings.fps_counter = true
	Settings.load_settings()
	check(not Settings.fps_counter, "the switch is saved and loaded")
	Settings.set_fps_counter(saved)
	Settings.save_settings()
