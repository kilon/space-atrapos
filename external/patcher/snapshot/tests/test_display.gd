extends TestCase
## Display settings: the frame drawn at the resolution picked, windowed or fullscreen.


func test_frames_drawn_at_the_picked_resolution() -> void:
	var S: GDScript = load("res://scripts/core/settings.gd")
	var base := Vector2i(1920, 1080)
	var p: Array = S.frame_plan(true, Vector2i(1920, 1080), Vector2i(2560, 1440), base)
	check(p[0] == Vector2i(1920, 1080) and is_equal_approx(p[1], 1.0), "fullscreen 1080p on a 1440p screen: drawn at 1080p (%s)" % [p])
	var w: Array = S.frame_plan(false, Vector2i(1920, 1080), Vector2i(2560, 1440), base)
	check(w == p, "windowed at the same resolution: drawn the same - going in or out changes only the window (%s)" % [w])
	p = S.frame_plan(false, Vector2i(1280, 720), Vector2i(2560, 1440), base)
	check(p[0] == Vector2i(1280, 720) and is_equal_approx(p[1], 720.0 / 1080.0), "720p: drawn at 720p, laid out the same (%s)" % [p])
	p = S.frame_plan(true, Vector2i(3840, 2160), Vector2i(1920, 1080), base)
	check(p[0] == Vector2i(1920, 1080), "never more than the screen (%s)" % [p])
	check(not Settings.available_resolutions().is_empty(), "resolutions offered")
