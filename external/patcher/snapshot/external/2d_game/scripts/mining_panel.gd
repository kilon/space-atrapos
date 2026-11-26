class_name MiningPanel
extends Control
## The mining readout above the toolbar while an asteroid is your target
## (Mining): the rock, what it's made of (once prospected), its veins, and the
## vein being cut - its heat on a bar with the cutting band in green, the
## resonance building while it's held there, the fragments cut so far.

var ship: Node2D
var _shown := false
var _cut := {}          # mineral -> fragments cut since this rock was picked
var _rock: Node2D
var _last_units := -1


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(560, 132)
	visible = false


## How long it stays after the laser stops (s), and how far from the rock it shows at all.
const LINGER := 3.0
const REACH := 1400.0

func _process(_delta: float) -> void:
	var rock: Node2D = ship.attack_target if ship and is_instance_valid(ship.attack_target) and ship.attack_target is Asteroid else null
	# Shown while you mine: the button held (or the autopilot at it), or a
	# few seconds after the laser last cut - not for as long as a rock stays
	# your target (let go, fly off: it goes).
	var mining: bool = ship != null and (ship.mining_hold or ship.mining_auto \
		or Time.get_ticks_msec() / 1000.0 - float(ship.mining_at) < LINGER)
	var on: bool = rock != null and mining and ship.global_position.distance_to(rock.global_position) < REACH
	if on != visible:
		visible = on
	if not on:
		return
	rock.settle()
	if rock != _rock:
		_rock = rock
		_cut = {}
		_last_units = -1
	# (what's been cut: counted from the veins going down)
	var units := 0
	for v in rock.veins:
		units += int(v["units"])
	if _last_units >= 0 and units < _last_units and ship.mining_vein >= 0 and ship.mining_vein < rock.veins.size() and ship.mining_last == "cut":
		var m: String = rock.veins[ship.mining_vein]["mineral"]
		_cut[m] = int(_cut.get(m, 0)) + (_last_units - units)
	_last_units = units
	if UI.redraw_due(self, 30.0):
		queue_redraw()


func _draw() -> void:
	var rock: Node2D = _rock
	if rock == null or not is_instance_valid(rock):
		return
	var font := NeonTheme.heavy_font()
	var fs := Settings.fs("hud", 14)
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(NeonTheme.BG, 0.82))
	draw_rect(r, Color(NeonTheme.CYAN, 0.45), false, 1.0)
	var x := 12.0
	var y := 20.0
	draw_string(font, Vector2(x, y), "MINING  ·  %s" % str(rock.display_name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, NeonTheme.HEAD)
	if not rock.scanned:
		draw_string(font, Vector2(x, y + 24), "Not prospected: its veins are hidden - cutting gives only rubble.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, fs - 1, UI.TEXT_DIM)
		draw_string(font, Vector2(x, y + 46), "Right-click it to scan what it holds and where its veins run.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, fs - 1, Color(1.0, 0.8, 0.45))
		return
	# Composition: a strip in the minerals' colours.
	var keys: Array = rock.comp.keys()
	keys.sort_custom(func(a, b): return rock.comp[a] > rock.comp[b])
	var cx := x
	var cw := size.x - 24
	for m in keys:
		var w: float = float(rock.comp[m]) * cw
		draw_rect(Rect2(cx, y + 8, w, 8), Color(Mining.mineral_color(m), 0.85))
		if w > 70.0:
			draw_string(font, Vector2(cx + 3, y + 30), "%s %d%%" % [Items.display_name(m).replace(" Ore", ""), roundi(float(rock.comp[m]) * 100.0)], HORIZONTAL_ALIGNMENT_LEFT, w - 4, fs - 3, Color(Mining.mineral_color(m).lightened(0.3), 0.95))
		cx += w
	var vi: int = ship.mining_vein
	if vi < 0 or vi >= rock.veins.size():
		draw_string(font, Vector2(x, y + 58), "All its veins are cut out." if rock.vein_near(ship.global_position) < 0 else "Hold the button on the rock to cut; click near a vein to pick it.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, fs - 1, UI.TEXT_DIM)
		return
	var v: Dictionary = rock.veins[vi]
	var col := Mining.mineral_color(v["mineral"])
	draw_string(font, Vector2(x, y + 54), "VEIN %d of %d  ·  %s  ·  %d / %d left" % [vi + 1, rock.veins.size(), Items.display_name(v["mineral"]).to_upper(), int(v["units"]), int(v["max"])],
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 1, col.lightened(0.3))
	# The heat bar: cold - the band - the strain - fracture.
	var bar := Rect2(x, y + 64, size.x - 160, 18)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position.x + bar.size.x * Mining.SLOW_FROM, bar.position.y, bar.size.x * (Mining.BAND.x - Mining.SLOW_FROM), bar.size.y), Color(0.9, 0.8, 0.3, 0.18))
	draw_rect(Rect2(bar.position.x + bar.size.x * Mining.BAND.x, bar.position.y, bar.size.x * (Mining.BAND.y - Mining.BAND.x), bar.size.y), Color(0.3, 1.0, 0.45, 0.35))
	draw_rect(Rect2(bar.position.x + bar.size.x * Mining.BAND.y, bar.position.y, bar.size.x * (1.0 - Mining.BAND.y), bar.size.y), Color(1.0, 0.3, 0.2, 0.3))
	var heat := clampf(float(v["heat"]), 0.0, 1.0)
	var hot := Color(0.4, 0.75, 1.0).lerp(Color(1.0, 0.45, 0.2), heat)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * heat, bar.size.y)), Color(hot, 0.55))
	var nx := bar.position.x + bar.size.x * heat
	draw_line(Vector2(nx, bar.position.y - 3), Vector2(nx, bar.end.y + 3), Color.WHITE, 2.5)
	draw_rect(bar, Color(1, 1, 1, 0.35), false, 1.0)
	var state := "COLD" if heat < Mining.SLOW_FROM else ("WARMING" if heat < Mining.BAND.x else ("CUTTING" if heat <= Mining.BAND.y else "TOO HOT"))
	var scol := UI.TEXT_DIM if heat < Mining.SLOW_FROM else (Color(0.95, 0.85, 0.4) if heat < Mining.BAND.x else (Color(0.4, 1.0, 0.55) if heat <= Mining.BAND.y else Color(1.0, 0.4, 0.3)))
	draw_string(font, Vector2(bar.end.x + 10, bar.position.y + 14), state, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, scol)
	# Resonance, and the haul.
	var res := float(v["res"])
	draw_string(font, Vector2(x, y + 102), "Resonance x%.2f" % res, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, Color(0.4, 1.0, 0.55) if res > 1.01 else UI.TEXT_DIM)
	var rb := Rect2(x + 140, y + 94, 120, 8)
	draw_rect(rb, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(rb.position, Vector2(rb.size.x * (res - 1.0) / (Mining.RESONANCE_MAX - 1.0), rb.size.y)), Color(0.4, 1.0, 0.55, 0.8))
	var haul := []
	for m in _cut:
		haul.append("%d %s" % [int(_cut[m]), Items.display_name(m).replace(" Ore", "").to_lower()])
	draw_string(font, Vector2(x + 280, y + 102), ("Cut: " + ", ".join(haul)) if not haul.is_empty() else "Hold the button on the rock; keep the heat in the green.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 300, fs - 2, UI.TEXT_DIM)
