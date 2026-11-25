class_name ShipScanner
extends Node2D
## Your ship's scanner (right-click in space, main.gd):
##  - on an asteroid (within ROCK_RANGE): a laser scan sweeps across it for
##    ROCK_TIME s; when it's done the rock stays highlighted with its kind and
##    the ore it holds (Asteroid.scanned).
##  - (empty space: the probe scanner - ProbeScanner, on the system map)
##  - in a signal site, an anomaly's node (anything with on_scanned() and a
##    scan_range) is scanned like a rock.
## Drawn in the world, above the ships (z_index).

const ROCK_RANGE := 1600.0
const ROCK_TIME := 1.3
const CYAN := Color(0.3, 0.9, 1.0)       # (the GUIs cyan)
const ORANGE := Color(1.0, 0.55, 0.15)

var ship: Node2D
var minimap: Control
var main: Node
var paths: Array = []               # (none now: signals are found by probes - ProbeScanner)
var _rock: Node2D                   # being scanned
var _rock_t := -1.0


func _ready() -> void:
	z_index = 8
	z_as_relative = false


func scanning() -> bool:
	return _rock_t >= 0.0


## Scans an asteroid (false if it's out of range).
func scan_rock(rock: Node2D) -> bool:
	if ship == null or not is_instance_valid(rock):
		return false
	var reach: float = float(rock.get("scan_range")) if rock.get("scan_range") != null else ROCK_RANGE
	if ship.global_position.distance_to(rock.global_position) > reach:
		ship.message.emit(("Out of scanner range - get within %.1fk of it" % (reach / 1000.0)) if reach >= 1000.0 else "Out of scanner range - fly closer to it")
		return false
	_rock = rock
	_rock_t = 0.0
	Sfx.play_world("space/scan_laser", rock.global_position, -2.0, 0.03)
	return true


func _process(delta: float) -> void:
	if _rock_t >= 0.0:
		_rock_t += delta
		if not is_instance_valid(_rock) or not _rock.is_inside_tree():
			_rock_t = -1.0
		elif _rock_t >= ROCK_TIME:
			_rock_t = -1.0
			Sfx.play("space/scan_done", -4.0)
			if _rock.has_method("on_scanned"):
				_rock.on_scanned()
			else:
				_rock.scanned = true
				# (the prospecting readout: what it's made of, its veins - Mining)
				var parts := []
				var keys: Array = _rock.comp.keys()
				keys.sort_custom(func(a, b): return _rock.comp[a] > _rock.comp[b])
				for m in keys:
					parts.append("%s %d%%" % [Items.display_name(m).replace(" Ore", ""), roundi(float(_rock.comp[m]) * 100.0)])
				var live: Array = _rock.veins.filter(func(v): return int(v["units"]) > 0)
				GameLog.post("Prospected: %s - %s. %d vein%s: %s." % [_rock.display_name, ", ".join(parts), live.size(), "" if live.size() == 1 else "s",
					", ".join(live.map(func(v): return "%s (%d)" % [Items.display_name(v["mineral"]).replace(" Ore", "").to_lower(), int(v["units"])]))], "info")
	queue_redraw()


func _draw() -> void:
	if _rock_t >= 0.0 and is_instance_valid(_rock) and ship:
		_draw_rock_scan()


## The asteroid scan, in the console's glowing style: a beam from the ship's
## nose like a route (soft glow, bright core, pulses running out along it)
## sweeping across the rock, a bright scan line over it, glowing target rings
## with light nodes round the rock, an orange arc filling as the scan runs and
## a readout above. Sizes in screen pixels.
func _draw_rock_scan() -> void:
	var px := 1.0 / maxf(get_canvas_transform().get_scale().x, 0.01)
	var nose: Vector2 = ship.global_transform * Vector2(0, -34.0)
	var c: Vector2 = _rock.global_position
	var r: float = _rock.hit_radius
	var u := _rock_t / ROCK_TIME
	var dir := nose.direction_to(c)
	var side := dir.orthogonal()
	var sweep := sin(u * TAU * 1.5) * 0.9   # back and forth across it
	var hit := c + side * sweep * r - dir * sqrt(maxf(0.0, 1.0 - sweep * sweep)) * r * 0.6
	var a := 1.0 - maxf(0.0, u - 0.85) / 0.15
	# The beam: a faint fan, then a glowing route to where it touches.
	draw_colored_polygon(PackedVector2Array([nose, c + side * r - dir * r * 0.2, c - side * r - dir * r * 0.2]), Color(CYAN, 0.05 * a))
	draw_line(nose, hit, Color(CYAN, 0.12 * a), 22.0 * px, true)
	draw_line(nose, hit, Color(CYAN, 0.3 * a), 9.0 * px, true)
	draw_line(nose, hit, Color(CYAN.lightened(0.5), 0.95 * a), 2.5 * px, true)
	var now := Time.get_ticks_msec() / 1000.0
	for q in 3:
		var t := fposmod(now * 1.6 + q / 3.0, 1.0)
		var p := nose.lerp(hit, t)
		draw_circle(p, 9.0 * px, Color(CYAN, 0.2 * a))
		draw_circle(p, 3.5 * px, Color(1, 1, 1, 0.9 * a))
	# The scan line over the rock.
	draw_line(hit - dir * r * 0.9, hit + dir * r * 0.4, Color(CYAN, 0.25 * a), 10.0 * px, true)
	draw_line(hit - dir * r * 0.9, hit + dir * r * 0.4, Color(CYAN.lightened(0.5), 0.9 * a), 2.0 * px, true)
	draw_circle(hit, (7.0 + 3.0 * sin(_rock_t * 40.0)) * px, Color(CYAN, 0.35 * a))
	draw_circle(hit, 3.5 * px, Color(1, 1, 1, 0.95 * a))
	# Target rings with nodes, turning slowly, and the progress arc.
	var ring := r * 1.25 + 10.0 * px
	draw_arc(c, ring, 0, TAU, 64, Color(CYAN, 0.14 * a), 12.0 * px, true)
	draw_arc(c, ring, 0, TAU, 64, Color(CYAN.lightened(0.3), 0.75 * a), 2.0 * px, true)
	for k in 6:
		var na := now * 0.6 + k * TAU / 6.0
		var np := c + Vector2.from_angle(na) * ring
		draw_circle(np, 7.0 * px, Color(CYAN, 0.25 * a))
		draw_circle(np, 3.0 * px, Color(CYAN.lightened(0.6), a))
	var outer := ring + 12.0 * px
	draw_arc(c, outer, -PI / 2.0, -PI / 2.0 + TAU * u, 64, Color(ORANGE, 0.25 * a), 10.0 * px, true)
	draw_arc(c, outer, -PI / 2.0, -PI / 2.0 + TAU * u, 64, Color(ORANGE.lightened(0.3), a), 3.0 * px, true)
	# Readout.
	var font := NeonTheme.heavy_font()
	var fs := int(Settings.fs("world", 18) * px)
	var at := c + Vector2(-160.0 * px, -outer - 16.0 * px)
	var label := "SCANNING  %d%%" % int(u * 100.0)
	draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, 320.0 * px, fs, int(5 * px), Color(0, 0, 0, 0.8 * a))
	draw_string(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, 320.0 * px, fs, Color(ORANGE.lightened(0.25), a))


## How far signal paths reach, and how close you must be to see a signal on
## the radar and the system map: a third of the
## current system across - twice the farthest gate, station or planet from the
## star, divided by three. Worked out once per system.
static var _range_sys := ""
static var _range := 0.0

static func signal_range(tree: SceneTree) -> float:
	var sys: String = Galaxy.current_system
	if sys != _range_sys or _range <= 0.0:
		var far := 0.0
		for g in ["gates", "stations", "planet_bodies"]:
			for n in tree.get_nodes_in_group(g):
				if n.global_position.distance_to(SignalSite.ORIGIN) > SignalSite.BOUNDS * 2.0:
					far = maxf(far, n.global_position.length())
		if far <= 0.0:
			return 20000.0   # (the system isn't built yet: don't remember this)
		_range_sys = sys
		_range = far * 2.0 / 3.0
	return _range


static func signal_visible(tree: SceneTree, at: Vector2, from: Vector2) -> bool:
	return from.distance_to(at) <= signal_range(tree)
