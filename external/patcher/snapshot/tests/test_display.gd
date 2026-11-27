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


## A window the size of the resolution picked stays on the screen: asked for where it would hang off the
## bottom (a playtest's bottom-left), moved up; one that fits stays where it was asked for.
func test_window_kept_on_screen() -> void:
	var usable := Rect2i(0, 0, 3840, 2099)   # (a 4K screen less its panel)
	check_eq(Settings.on_screen(Vector2i(0, 1020), Vector2i(3840, 2160), usable), Vector2i(0, 0), "a 4K window at the bottom-left: moved to the top")
	check_eq(Settings.on_screen(Vector2i(0, 1020), Vector2i(1920, 1080), usable), Vector2i(0, 1019), "1080p at the bottom-left: moved up just enough")
	check_eq(Settings.on_screen(Vector2i(100, 100), Vector2i(1920, 1080), usable), Vector2i(100, 100), "one that fits: where it was asked for")
	check_eq(Settings.on_screen(Vector2i(3000, 50), Vector2i(1600, 900), usable), Vector2i(2240, 50), "off the right edge: moved left")
