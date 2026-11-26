class_name SignalBeacon
extends Node2D
## A located signal source in space (SignalSites): a pulsing marker in its
## kind's colour with its name. The ENTER button over it (LandingUI) drops
## you into its site (main.request_site); a finished one fades away.

const ENTER_RANGE := 700.0          # this close, ENTER drops you in at once (else you fly there first)

var sig: Dictionary = {}
var _t := 0.0


func _ready() -> void:
	add_to_group("signal_beacons")
	z_index = -2
	_t = randf() * TAU
	position = SignalSites.pos(sig)


func title() -> String:
	return SignalSites.info(sig["kind"])["name"]


func color() -> Color:
	return SignalSites.info(sig["kind"])["color"]


## Shown in space (located and not done yet).
func active() -> bool:
	return bool(sig.get("located", false)) and not bool(sig.get("done", false))


func _process(delta: float) -> void:
	visible = active()
	if visible:
		_t += delta
		if on_screen():
			queue_redraw()   # (a system can have dozens: only the ones you can see)


## On screen (its rings and its label - 400 px either way - in the view).
func on_screen() -> bool:
	var c := get_global_transform_with_canvas()
	var reach := 400.0 * c.get_scale().x
	return get_viewport_rect().grow(reach).has_point(c.origin)


func _draw() -> void:
	if not on_screen():
		return   # (every one draws once as it's made - dozens of labels, ~10 ms of a scene's first frame; drawn when it comes into view)
	var c := color()
	var pulse := 0.5 + 0.5 * sin(_t * 2.4)
	draw_circle(Vector2.ZERO, 70.0 + 10.0 * pulse, Color(c, 0.06 + 0.05 * pulse))
	# Two dashed rings turning opposite ways.
	for ring in [[46.0, 1.0, 12], [64.0, -0.6, 18]]:
		var n: int = ring[2]
		for i in n:
			if i % 2 == 0:
				var a0: float = i * TAU / n + _t * float(ring[1])
				draw_arc(Vector2.ZERO, ring[0], a0, a0 + TAU / n, 6, Color(c, 0.75), 2.5, true)
	# The signal's waveform in the middle.
	var pts := PackedVector2Array()
	for k in 25:
		var x := -26.0 + k * 52.0 / 24.0
		var env := 1.0 - absf(x) / 26.0
		pts.append(Vector2(x, sin(x * 0.55 + _t * 6.0) * 14.0 * env * (0.6 + 0.4 * pulse)))
	draw_polyline(pts, Color(c.lightened(0.3), 0.95), 2.5, true)
	var font := ThemeDB.fallback_font
	var fs := Settings.fs("world", 15)
	var label := title().to_upper()
	draw_string_outline(font, Vector2(-180, 98), label, HORIZONTAL_ALIGNMENT_CENTER, 360, fs, 4, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(-180, 98), label, HORIZONTAL_ALIGNMENT_CENTER, 360, fs, c.lightened(0.25))
	var lv := SignalSites.level_info(sig)
	var sub := "signal source  ·  %s" % str(lv["name"]).to_lower()
	if sig.get("kind", "") == "ring":
		sub = "local space  ·  the ring of %s" % str(sig.get("planet", ""))
	draw_string_outline(font, Vector2(-180, 98 + fs + 4), sub, HORIZONTAL_ALIGNMENT_CENTER, 360, maxi(Settings.MIN_FONT, fs - 3), 3, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(-180, 98 + fs + 4), sub, HORIZONTAL_ALIGNMENT_CENTER, 360, maxi(Settings.MIN_FONT, fs - 3), Color(c, 0.7))
	# The level's mark: one to four pips in its colour.
	var pips := 0 if sig.get("kind", "") == "ring" else (SignalSites.LEVELS.keys() as Array).find(SignalSites.level(sig)) + 1
	for i in pips:
		draw_circle(Vector2((i - (pips - 1) / 2.0) * 16.0, 98 + fs * 2 + 14), 5.0, lv["color"])
