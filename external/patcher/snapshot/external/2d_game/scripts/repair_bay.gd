class_name RepairBay
extends HBoxContainer
## The Repair Bay (a Ship Computer and Field Computer tab): your ship's and
## your automaton's parts (Parts), opened up one at a time on the operating
## table and repaired by hand, like surgery:
##   - the schematic and the part list on the left: how well each part works,
##     the faults found in it and the "?" of damage not yet traced;
##   - the table: the part's casing (bolts to undo - opposite ones, never
##     neighbours, or the casing warps and cracks), then its components, the
##     cables between them and the faults the scanner has found;
##   - the right: the vitals (temperature, pressure, power, a pulse that
##     races as the part heats), the power breaker, the tools, the scan modes,
##     the spare parts you carry and the faults found here.
## Tools: the scanner (a lens swept over the part: faults of its mode show,
## and are marked once it rests on them), the welder (trace a
## crack slowly; too fast leaves gaps, too long in one place burns), the
## soldering iron (each strand to its own colour; with the power on it
## shocks), the sealant (only while the pressure is low), the calibrator (two
## dials: frequency and phase onto the reference wave) and the forceps (open
## the clamps, pull the wreck out, a spare turned the right way into the
## socket, clamps shut). Mistakes cost work, never a new fault (faults come
## only from hits: Parts.hit): heat past the limit cuts the welder out and
## cracks the bead back, a shock hurts, a warped casing seizes the bolts. The
## game goes on meanwhile (the Ship Computer closes when you're hit).
##
## The automaton is operated on as a body (Surgery): the table shows its
## anatomy in four layers (the scan modes' row becomes the layers), the tools
## are a surgeon's (SURGERY_TOOLS), the breaker is a nerve block.

var data: Node          # PlayerData (in space); null on a planet
var ship: Node2D        # the ship (in space)
var surface: Node       # the planet surface (on foot)

var which := "ship"
var pid := ""
var tool := "scanner"
var scan := "structure"
var layer := "muscles"   # the automaton: the layer of its anatomy shown (Parts.LAYERS)

const TOOLS := [
	["scanner", "Scanner", "Sweep the lens over the part. Faults that show in the selected mode light up, and are marked once the lens rests on them. Without a Deep Scanner the casing blocks it - open the part first."],
	["welder", "Welder", "Hold the button and trace a found crack from end to end - slowly: too fast leaves it open; resting in one place burns through. Watch the temperature."],
	["solder", "Soldering iron", "Drag each frayed strand of a burnt cable onto the terminal of its own colour. Cut the part's power first: a live cable shocks you and burns more wiring."],
	["sealant", "Sealant", "Hold over a found leak while its pressure gauge is low (green). Sealant put on at high pressure is blown away."],
	["calibrator", "Calibrator", "On a misaligned component: drag the two dials up and down - frequency, then phase - until your wave lies on the reference, and hold it there."],
	["forceps", "Forceps", "On a wrecked component: click its two clamps open, drag it out, click the empty socket to take a spare, turn it with the wheel or right-click until its notch meets the socket's, click to seat it, then click the clamps shut."],
]

## The automaton's (Surgery).
const SURGERY_TOOLS := [
	["scanner", "Scanner", "Sweep the lens over the body. It shows the faults of the layer you're looking at - pick the layer below - and marks one once it rests on it. The deeper layers need a Mk II scanner."],
	["scalpel", "Scalpel", "A fault under the muscle (a vessel, a nerve, a bone) is reached through an incision: hold the button and draw the blade along the dashed line over it - steadily: too fast and it skips."],
	["suture", "Suture", "A tear: click each mark along it to put a stitch there. With an incision open, its marks too - to close it up."],
	["fuser", "Bone fuser", "A fracture: hold the button and trace the break from end to end - slowly: too fast and the bone doesn't knit; resting in one place overheats it. Watch the temperature."],
	["clamp", "Clamp", "A bleeding vessel: click the ring upstream of the hole to clamp it - the pressure stays down while it holds (not for long: then the tissue needs its blood). Click it again to take it off."],
	["sealant", "Sealant", "Hold over a vessel's hole while its pressure is low (the gauge in the green) - clamp it, or wait for the low of the pulse. Sealant put on at high pressure is washed away."],
	["splicer", "Splicer", "A burnt nerve: drag each frayed fibre onto the end of its own colour. Numb the region first (the nerve block): a live nerve shocks."],
	["tuner", "Tuner", "A spasm (a heart out of rhythm): drag the two dials up and down - rate, then phase - until your wave lies on the reference, and hold it there."],
	["forceps", "Forceps", "A destroyed structure: click its two ties undone, drag it out, click the wound to take a spare as a graft, turn it with the wheel or right-click until it lies the way the tissue runs, click to graft it, then click the ties."],
]

var _ops := {}   # (body:part) -> the operation's state (bolts, heat...): Table
var _schem: Schematic
var _table: Table
var _surgery: Surgery
var _tool_grid: GridContainer
var _vitals: Vitals
var _parts_box: VBoxContainer
var _tool_btns := {}
var _scan_box: HBoxContainer
var _spares_box: GridContainer
var _faults_box: VBoxContainer
var _power: Button
var _help: Label
var _status: Label
var _body_btns := {}


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	# Left: the body, its schematic, its parts.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	var bodies := HBoxContainer.new()
	for b in ["ship", "automaton"]:
		var btn := UI.button(Parts.BODIES[b]["name"].to_upper(), _pick_body.bind(b), 16)
		btn.toggle_mode = true
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.tooltip_text = "The %s's parts." % Parts.BODIES[b]["name"].to_lower()
		bodies.add_child(btn)
		_body_btns[b] = btn
	left.add_child(bodies)
	_schem = Schematic.new()
	_schem.bay = self
	_schem.custom_minimum_size = Vector2(300, 300)
	left.add_child(_schem)
	_parts_box = VBoxContainer.new()
	_parts_box.add_theme_constant_override("separation", 3)
	left.add_child(_parts_box)
	# Middle: the operating table.
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(mid)
	_status = UI.label("", 18, NeonTheme.HEAD)
	mid.add_child(_status)
	_table = Table.new()
	_table.bay = self
	_table.custom_minimum_size = Vector2(840, 600)
	_table.size_flags_horizontal = SIZE_EXPAND_FILL
	_table.size_flags_vertical = SIZE_EXPAND_FILL
	mid.add_child(_table)
	_surgery = Surgery.new()
	_surgery.bay = self
	_surgery.custom_minimum_size = Vector2(840, 600)
	_surgery.size_flags_horizontal = SIZE_EXPAND_FILL
	_surgery.size_flags_vertical = SIZE_EXPAND_FILL
	_surgery.visible = false
	mid.add_child(_surgery)
	_help = UI.label("", 15, UI.TEXT_DIM)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(0, 66)
	mid.add_child(_help)
	# Right: vitals, power, tools, scan modes, spares, faults.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(330, 0)
	right.add_theme_constant_override("separation", 6)
	add_child(right)
	right.add_child(UI.section("VITALS"))
	_vitals = Vitals.new()
	_vitals.bay = self
	_vitals.custom_minimum_size = Vector2(330, 150)
	right.add_child(_vitals)
	_power = UI.button("", _toggle_power, 15)
	_power.tooltip_text = "The part's breaker. Off, the part does nothing (the ship flies without it) - but its cables are safe to solder."
	right.add_child(_power)
	right.add_child(UI.section("TOOLS"))
	_tool_grid = GridContainer.new()
	_tool_grid.add_theme_constant_override("h_separation", 6)
	_tool_grid.add_theme_constant_override("v_separation", 4)
	right.add_child(_tool_grid)
	_scan_box = HBoxContainer.new()
	_scan_box.add_theme_constant_override("separation", 4)
	right.add_child(_scan_box)
	right.add_child(UI.section("SPARE PARTS"))
	_spares_box = GridContainer.new()
	_spares_box.columns = 3
	right.add_child(_spares_box)
	right.add_child(UI.section("FAULTS FOUND HERE"))
	_faults_box = VBoxContainer.new()
	right.add_child(_faults_box)
	_pick_body("automaton" if surface != null and data == null else "ship")


func refresh() -> void:
	if _table == null:
		return
	_fill()


## The tools of the body on the table: the ship's, or a surgeon's.
func tools() -> Array:
	return SURGERY_TOOLS if which == "automaton" else TOOLS


## The table in use: the casing and its components, or the body's anatomy.
func view() -> Control:
	return _surgery if which == "automaton" else _table


func redraw_view() -> void:
	if which == "automaton":
		_surgery.repaint()
	else:
		_table.queue_redraw()


func _fill_tools() -> void:
	UI.clear(_tool_grid)
	_tool_btns = {}
	var ts := tools()
	_tool_grid.columns = 3 if ts.size() > 6 else 2
	for t in ts:
		var b := UI.button(t[1], set_tool.bind(t[0]), 15 if ts.size() <= 6 else 14)
		b.toggle_mode = true
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.tooltip_text = t[2]
		_tool_grid.add_child(b)
		_tool_btns[t[0]] = b
	if not ts.any(func(t): return t[0] == tool):
		tool = "scanner"


# --- The state ----------------------------------------------------------------------

## The player's condition (Parts) - in space PlayerData's, on a planet the surface's player state's.
func cond() -> Dictionary:
	if data:
		return data.condition
	if surface:
		var p: Dictionary = surface.state["player"]
		if not p.get("condition") is Dictionary:
			p["condition"] = {}
		return p["condition"]
	return {}


## Where items are kept: the pack, then the hold.
func _stores() -> Array:
	if data:
		return [data.carried, data.items]
	if surface:
		var p: Dictionary = surface.state["player"]
		if not p.get("items") is Dictionary:
			p["items"] = {}
		return [Inventory.carried(p), p["items"]]
	return []


func count(id: String) -> int:
	var n := 0
	for st in _stores():
		n += int(st.get(id, 0))
	return n


func items_all() -> Dictionary:
	var out := {}
	for st in _stores():
		for id in st:
			out[id] = int(out.get(id, 0)) + int(st[id])
	return out


func use_item(id: String) -> bool:
	for st in _stores():
		if int(st.get(id, 0)) > 0:
			st[id] = int(st[id]) - 1
			if int(st[id]) <= 0:
				st.erase(id)
			if data:
				data.changed.emit()
			return true
	return false


func faults() -> Array:
	if pid == "":
		return []
	return Parts.part(cond(), which, pid)["faults"]


func fault(id: int) -> Dictionary:
	for f in faults():
		if int(f["id"]) == id:
			return f
	return {}


## The operation on the table: {bolts, open, lift, stress, heat, shock, f: {fault id: {...}}, scan: {...}}.
func op() -> Dictionary:
	var k := which + ":" + pid
	if not _ops.has(k):
		var n := 6
		var b := []
		b.resize(n)
		b.fill(true)
		_ops[k] = {"bolts": b, "open": false, "lift": 0.0, "stress": 0.0, "heat": 0.0, "shock": 0.0, "f": {}, "scan": {}, "last_bolt": -1, "seized": 0, "cuts": {}}
	return _ops[k]


func powered() -> bool:
	return pid != "" and not Parts.part(cond(), which, pid).get("off", false)


# --- Actions ------------------------------------------------------------------------

func _pick_body(b: String) -> void:
	_close_up()
	which = b
	pid = Parts.BODIES[b]["parts"].keys()[0]
	for k in _body_btns:
		_body_btns[k].set_pressed_no_signal(k == b)
	_table.visible = b != "automaton"
	_surgery.visible = b == "automaton"
	_fill_tools()
	if b == "automaton":
		_surgery.opened()
	_fill()


func pick_part(p: String) -> void:
	if p == pid:
		return
	_close_up()
	pid = p
	Sfx.play("space/select", -8.0)
	if which == "automaton":
		_surgery.opened()
	_fill()


## Leaving a part: its bolts go back in (the operation's done for now).
func _close_up() -> void:
	if pid == "":
		return
	var o := op()
	if which == "automaton":
		if not o["cuts"].is_empty():   # (its incisions are closed up)
			o["cuts"] = {}
			o["f"] = {}
		return
	if o["open"] or o["bolts"].has(false):
		o["bolts"].fill(true)
		o["open"] = false
		o["lift"] = 0.0
		o["f"] = {}


func set_tool(t: String) -> void:
	tool = t
	for k in _tool_btns:
		_tool_btns[k].set_pressed_no_signal(k == t)
	_update_help()
	redraw_view()


func set_scan(m: String) -> void:
	scan = m
	Sfx.play("space/scan_pulse", -14.0)
	_fill_scans()
	_table.queue_redraw()


## The automaton: the layer of its anatomy shown.
func set_layer(l: String) -> void:
	layer = l
	Sfx.play("space/scan_pulse", -14.0)
	_fill_scans()
	_update_help()
	_surgery.repaint()


func _toggle_power() -> void:
	if pid == "" or Parts.info(which, pid).get("vital", false):
		return
	var p := Parts.part(cond(), which, pid)
	p["off"] = not p.get("off", false)
	Sfx.play("space/select" if p["off"] else "space/scan_pulse", -6.0)
	if which == "automaton":
		log_line("%s: %s." % [Parts.info(which, pid)["name"], "numbed - it does nothing till the block is lifted" if p["off"] else "the nerve block lifted"], "info")
	else:
		log_line("%s power %s." % [Parts.info(which, pid)["name"], "cut" if p["off"] else "restored"], "info")
	changed()


## Something about the parts changed: the stats follow (the ship's, the automaton's).
func changed() -> void:
	if data:
		if ship and ship.has_method("apply_tech"):
			ship.apply_tech()
		data.changed.emit()
	elif surface and surface.has_method("refresh_gear"):
		surface.refresh_gear()
	_fill()


func log_line(text: String, kind := "info") -> void:
	GameLog.post(text, kind)
	view().flash(text, Color(1.0, 0.45, 0.35) if kind == "danger" else (Color(0.5, 1.0, 0.6) if kind == "good" else Color(1, 0.9, 0.7)))


## A fault fixed on the table.
func fixed(f: Dictionary) -> void:
	var comp: Array = Parts.comps(which, pid)[int(f["comp"])]
	var what: String = Parts.fault_info(which, pid, f)["name"]
	Parts.clear_fault(cond(), which, pid, int(f["id"]))
	op()["f"].erase(int(f["id"]))
	Sfx.play("space/repair", -4.0)
	log_line(("Mended: %s - %s." if which == "automaton" else "Fixed: %s in the %s.") % [what.to_lower(), str(comp[1]).to_lower()], "good")
	changed()


## A mishap at the table (a warped casing, an overheated welder): it costs
## you work, never a new fault - faults come only from hits to the hull (or the
## automaton's body): Parts.hit.
func mishap(why: String, what: String) -> void:
	Sfx.play("space/spark", -2.0)
	log_line("%s! %s" % [why, what], "danger")
	changed()


## A shock from live wiring: the pulse jumps; on foot it hurts you too.
func shock(text := "Shock! The cable is live - cut the power first.") -> void:
	var o := op()
	o["shock"] = 1.0
	o["heat"] = minf(100.0, float(o["heat"]) + 25.0)
	Sfx.play("space/hazard_zap", -2.0)
	if which == "automaton" and surface and surface.get("pilot") != null:
		surface.pilot.hp = maxf(1.0, surface.pilot.hp - 8.0)
	log_line(text, "danger")


# --- The panels ---------------------------------------------------------------------

func _fill() -> void:
	if _table == null or pid == "":
		return
	var c := cond()
	Parts.body(c, which)
	# The parts.
	UI.clear(_parts_box)
	for p in Parts.BODIES[which]["parts"]:
		var h := Parts.health(c, which, p)
		var fs: Array = Parts.part(c, which, p)["faults"]
		var found := fs.filter(func(f): return f.get("found", false)).size()
		var hidden := fs.size() - found
		var off: bool = Parts.part(c, which, p).get("off", false)
		var txt := "%s   %d%%" % [Parts.info(which, p)["name"], roundi(h * 100.0)]
		if found > 0:
			txt += "   ⚠%d" % found
		if hidden > 0:
			txt += "   ?"
		if off:
			txt += "   OFF"
		var b := UI.button(txt, pick_part.bind(p), 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.set_pressed_no_signal(p == pid)
		var col := Color(0.55, 1.0, 0.6).lerp(Color(1.0, 0.35, 0.25), 1.0 - h)
		b.add_theme_color_override("font_color", col if not off else Color(0.6, 0.6, 0.6))
		b.tooltip_text = "%s: %s.\nWorking at %d%%%s." % [Parts.info(which, p)["name"], Parts.info(which, p)["what"], roundi(h * 100.0),
			("; %d fault%s found" % [found, "s" if found != 1 else ""]) if found else ""] + ("\nDamage not yet traced: scan it." if hidden > 0 else "")
		_parts_box.add_child(b)
	_fill_scans()
	# The spares.
	UI.clear(_spares_box)
	for k in Parts.SPARE_OF:
		var id: String = Parts.SPARE_OF[k]
		var row := HBoxContainer.new()
		var icon := SpareIcon.new()
		icon.kind = k
		icon.custom_minimum_size = Vector2(30, 30)
		row.add_child(icon)
		row.add_child(UI.label("×%d" % count(id), 15, Color.WHITE if count(id) > 0 else UI.TEXT_DIM))
		row.tooltip_text = "%s: %d (in your pack and hold).\n%s" % [Items.display_name(id), count(id), Items.ITEMS[id]["desc"]]
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		_spares_box.add_child(row)
	# The faults found here.
	UI.clear(_faults_box)
	var any := false
	for f in faults():
		if not f.get("found", false):
			continue
		any = true
		var fk: Dictionary = Parts.fault_info(which, pid, f)
		var comp: Array = Parts.comps(which, pid)[int(f["comp"])]
		var b := UI.button("%s  ·  %s" % [fk["name"], comp[1]], _take_for.bind(int(f["id"])), 14)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "%s (severity %d%%)\n%s\nClick: take the %s." % [fk["name"], roundi(float(f["sev"]) * 100.0), fk["desc"], _tool_name(fk["tool"]).to_lower()]
		if which == "automaton":
			b.tooltip_text += "\nLayer: %s." % str(Parts.LAYER_INFO[Parts.comp_layer(which, pid, int(f["comp"]))]["name"]).to_lower()
		_faults_box.add_child(b)
	var hidden_n := faults().filter(func(f): return not f.get("found", false)).size()
	if not any:
		_faults_box.add_child(UI.label("None yet." if hidden_n > 0 else "None.", 14, UI.TEXT_DIM))
	if hidden_n > 0:
		_faults_box.add_child(UI.label("Untraced damage: scan the part (%s)." % ", ".join(_modes_missing()), 13, UI.TEXT_DIM) if not _modes_missing().is_empty() \
			else UI.label("Untraced damage: scan the part.", 13, UI.TEXT_DIM))
	var vital: bool = Parts.info(which, pid).get("vital", false)
	if which == "automaton":
		_power.text = ("NERVE BLOCK: none  (vital - can't be numbed)" if vital else ("NERVE BLOCK: off  - numb it" if powered() else "NERVE BLOCK: ON  - lift it"))
		_power.tooltip_text = "Numbs this part of the body: it does nothing while it's numb - but its nerves are safe to splice."
	else:
		_power.text = ("POWER: ON  (vital - can't be cut)" if vital else ("POWER: ON  - cut it" if powered() else "POWER: OFF  - restore it"))
		_power.tooltip_text = "The part's breaker. Off, the part does nothing (the ship flies without it) - but its cables are safe to solder."
	_power.disabled = vital
	var h2 := Parts.health(c, which, pid)
	_status.text = "%s  ·  %s  ·  working at %d%%" % [Parts.BODIES[which]["name"].to_upper(), Parts.info(which, pid)["name"], roundi(h2 * 100.0)]
	set_tool(tool)
	_schem.queue_redraw()


## A fault in the list clicked: its tool in hand (the automaton's: and its layer shown).
func _take_for(id: int) -> void:
	var f := fault(id)
	if f.is_empty():
		return
	if which == "automaton":
		var l := Parts.comp_layer(which, pid, int(f["comp"]))
		if l != layer:
			set_layer(l)
		# (a fault still under the muscle: the scalpel first)
		set_tool(Parts.fault_info(which, pid, f)["tool"] if _surgery.reachable(f) else "scalpel")
	else:
		set_tool(Parts.fault_info(which, pid, f)["tool"])


## Scan modes of the faults in this part you have no scanner mode for.
func _modes_missing() -> Array:
	var out := []
	if which == "automaton":
		var layers := Parts.scan_layers(items_all())
		for f in faults():
			var l := Parts.comp_layer(which, pid, int(f["comp"]))
			if not f.get("found", false) and f["kind"] != "wreck" and not l in layers:
				var n := "the %s layer needs a Mk II scanner" % str(Parts.LAYER_INFO[l]["name"]).to_lower()
				if not n in out:
					out.append(n)
		return out
	var have := Parts.scan_modes(items_all())
	for f in faults():
		var m: String = Parts.FAULTS[f["kind"]]["scan"]
		if not f.get("found", false) and not m in have and not Parts.SCANS[m]["name"] in out:
			out.append(Parts.SCANS[m]["name"])
	return out.map(func(n): return "needs the %s mode: a Mk II scanner" % n)


func _fill_scans() -> void:
	UI.clear(_scan_box)
	if which == "automaton":
		# The body's layers (the scanner finds the faults of the one shown).
		var reads := Parts.scan_layers(items_all())
		for i in Parts.LAYERS.size():
			var l: String = Parts.LAYERS[i]
			var info: Dictionary = Parts.LAYER_INFO[l]
			var lb := UI.button("%d %s" % [i + 1, info["name"]], set_layer.bind(l), 13)
			lb.toggle_mode = true
			lb.set_pressed_no_signal(l == layer)
			lb.size_flags_horizontal = SIZE_EXPAND_FILL
			lb.add_theme_color_override("font_color", info["color"])
			lb.tooltip_text = "%s: %s%s" % [info["name"], info["desc"], "" if l in reads else "\nYour scanner doesn't read this deep: finding faults here needs a Diagnostic Scanner Mk II (stations' supplies)."]
			_scan_box.add_child(lb)
		return
	var have := Parts.scan_modes(items_all())
	if not scan in have:
		scan = have[0]
	for m in Parts.SCAN_ORDER:
		var b := UI.button(Parts.SCANS[m]["name"], set_scan.bind(m), 13)
		b.toggle_mode = true
		b.set_pressed_no_signal(m == scan)
		b.disabled = not m in have
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_color_override("font_color", Parts.SCANS[m]["color"])
		b.tooltip_text = "%s scan: %s%s" % [Parts.SCANS[m]["name"], Parts.SCANS[m]["desc"], "" if m in have else "\nNeeds a Diagnostic Scanner Mk II (stations' supplies)."]
		_scan_box.add_child(b)


func _tool_name(t: String) -> String:
	for x in tools():
		if x[0] == t:
			return x[1]
	return t


func _update_help() -> void:
	if _help == null:
		return
	var t := ""
	for x in tools():
		if x[0] == tool:
			t = "%s: %s" % [x[1], x[2]]
	if which == "automaton":
		var info: Dictionary = Parts.LAYER_INFO[layer]
		_help.text = "%s  (Layer %d, %s: %s)" % [t, Parts.LAYERS.find(layer) + 1, str(info["name"]).to_lower(), info["desc"]]
		return
	if tool == "scanner":
		t += "  (%s: %s)" % [Parts.SCANS[scan]["name"], Parts.SCANS[scan]["desc"]]
	if pid != "" and not op()["open"] and not (tool == "scanner" and Parts.deep_scan(items_all())):
		t = "The casing is closed: click its bolts to undo them - opposite ones in turn, never two neighbours.  " + t
	_help.text = t


# --- The operating table -----------------------------------------------------------------

class Table extends Control:
	var bay: RepairBay
	var _mouse := Vector2(-999, -999)
	var _down := false
	var _down_at := Vector2.ZERO
	var _still := 0.0          # s the welder has rested in one place
	var _speed := 0.0          # px/s the mouse moves
	var _since_move := 0.0     # s since it last moved
	var _schem_k := 0
	var _drag := {}            # what's being dragged: {"kind": "strand"/"dial"/"wreck", ...}
	var _held_spare := -1      # forceps: a spare in hand, turned (0..3)
	var _flash_text := ""
	var _flash_col := Color.WHITE
	var _flash_t := 0.0
	var _flash_at := Vector2.ZERO
	var _t := 0.0

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # (the rendered art drawn smaller than it was rendered)
		mouse_filter = MOUSE_FILTER_STOP
		clip_contents = true
		mouse_exited.connect(func(): _mouse = Vector2(-999, -999); _down = false)

	func flash(text: String, col: Color) -> void:
		_flash_text = text
		_flash_col = col
		_flash_t = 2.4
		_flash_at = _mouse if _mouse.x > -900 else size * 0.5

	# -- geometry --

	func area() -> Rect2:
		return Rect2(Vector2(36, 36), size - Vector2(72, 72))

	func casing() -> Rect2:
		return area().grow(-10)

	func bolt_pos(i: int) -> Vector2:
		var r := casing().grow(-18)
		var pts := [r.position, Vector2(r.get_center().x, r.position.y), Vector2(r.end.x, r.position.y),
			r.end, Vector2(r.get_center().x, r.end.y), Vector2(r.position.x, r.end.y)]
		return pts[i]

	func n_comps() -> int:
		return Parts.comps(bay.which, bay.pid).size()

	func comp_size() -> float:
		var n := n_comps()
		var cols := 3 if n > 4 or n == 3 else 2
		var rows := ceili(n / float(cols))
		var a := area()
		return minf(a.size.x / (cols * 3.2), a.size.y / (rows * 2.9))

	func comp_pos(i: int) -> Vector2:
		var n := n_comps()
		var cols := 3 if n > 4 or n == 3 else 2
		var rows := ceili(n / float(cols))
		var a := area().grow(-30)
		var row := i / cols
		var in_row := mini(cols, n - row * cols)
		var col := i % cols
		var x := a.position.x + a.size.x * (col + 0.5 + (cols - in_row) * 0.5) / cols
		var y := a.position.y + a.size.y * (row + 0.5) / rows
		# (a little offset each, from the part: not a perfect grid)
		var h := hash(bay.pid + str(i))
		return Vector2(x + float(h % 41 - 20), y + float((h / 41) % 31 - 15))

	## The cable into component i: from the breaker (the table's left edge) or the one before it.
	func cable(i: int) -> Array:
		var b := comp_pos(i)
		var a := comp_pos(i - 1) if i > 0 else Vector2(area().position.x + 4, area().get_center().y)
		return [a, b]

	func _rng(f: Dictionary) -> RandomNumberGenerator:
		var r := RandomNumberGenerator.new()
		r.seed = int(f.get("seed", 1)) * 7919 + int(f["id"])
		return r

	func crack_pts(f: Dictionary) -> PackedVector2Array:
		var r := _rng(f)
		var c := comp_pos(int(f["comp"]))
		var s := comp_size()
		var a0 := r.randf() * TAU
		var dir := Vector2.from_angle(a0)
		var nrm := dir.orthogonal()
		var pts := PackedVector2Array()
		var n := 7
		for i in n:
			var t := (i / float(n - 1)) * 2.0 - 1.0
			pts.append(c + dir * t * s * 1.1 + nrm * (r.randf_range(-0.28, 0.28) * s if i > 0 and i < n - 1 else 0.0))
		return pts

	## The crack cut into short pieces (each welded on its own).
	func crack_bits(f: Dictionary) -> Array:
		var pts := crack_pts(f)
		var out := []
		for i in pts.size() - 1:
			for k in 4:
				out.append([pts[i].lerp(pts[i + 1], k / 4.0), pts[i].lerp(pts[i + 1], (k + 1) / 4.0)])
		return out

	## A burnt cable: the gap's two ends and the strands' colours ({l: [pos], r: [pos], cols, order}).
	func burn_geo(f: Dictionary) -> Dictionary:
		var ab := cable(int(f["comp"]))
		var a: Vector2 = ab[0]
		var b: Vector2 = ab[1]
		var mid := a.lerp(b, 0.5)
		var d := (b - a).normalized()
		var nrm := d.orthogonal()
		var r := _rng(f)
		var palette := [Color(1.0, 0.3, 0.25), Color(1.0, 0.85, 0.2), Color(0.3, 0.6, 1.0), Color(0.4, 1.0, 0.45), Color(0.95, 0.95, 0.95)]
		var cols := []
		while cols.size() < 3:
			var c: Color = palette[r.randi() % palette.size()]
			if not c in cols:
				cols.append(c)
		var order := [0, 1, 2]
		for i in range(2, 0, -1):
			var j := r.randi() % (i + 1)
			var tmp: int = order[i]
			order[i] = order[j]
			order[j] = tmp
		if order == [0, 1, 2]:
			order = [2, 0, 1]
		var l := []
		var rr := []
		for k in 3:
			l.append(mid - d * 34.0 + nrm * (k - 1) * 16.0)
			rr.append(mid + d * 34.0 + nrm * (k - 1) * 16.0)
		return {"l": l, "r": rr, "cols": cols, "order": order, "a": a, "b": b, "mid": mid}

	func leak_pos(f: Dictionary) -> Vector2:
		var r := _rng(f)
		return comp_pos(int(f["comp"])) + Vector2.from_angle(r.randf() * TAU) * comp_size() * 0.5

	## Where a fault is (for the scanner).
	func anchor(f: Dictionary) -> Vector2:
		match str(f["kind"]):
			"burn":
				return burn_geo(f)["mid"]
			"leak":
				return leak_pos(f)
		return comp_pos(int(f["comp"]))

	func clamp_pos(f: Dictionary, k: int) -> Vector2:
		return comp_pos(int(f["comp"])) + Vector2((k * 2 - 1) * comp_size() * 1.25, 0)

	func notch(f: Dictionary) -> int:
		return _rng(f).randi() % 4

	func fstate(f: Dictionary) -> Dictionary:
		var fs: Dictionary = bay.op()["f"]
		var id := int(f["id"])
		# (Made anew when the fault changes kind under the hands: a burn beaten
		# past repair is a wreck now, the same fault - its old work doesn't apply.)
		if not fs.has(id) or str(fs[id].get("kind", "")) != str(f["kind"]):
			var r := _rng(f)
			match str(f["kind"]):
				"crack":
					var done := []
					done.resize(crack_bits(f).size())
					done.fill(false)
					fs[id] = {"done": done}
				"burn":
					fs[id] = {"joined": [false, false, false]}
				"leak":
					fs[id] = {"prog": float(f.get("prog", 0.0)), "w": r.randf_range(1.3, 2.1), "ph": r.randf() * TAU}
				"drift":
					var f0 := r.randf_range(1.2, 3.2)
					var p0 := r.randf() * TAU
					fs[id] = {"f0": f0, "p0": p0, "f": clampf(f0 + (r.randf_range(0.6, 1.2) * (1 if r.randf() < 0.5 else -1)), 0.6, 4.0),
						"p": wrapf(p0 + r.randf_range(1.2, 2.6), 0.0, TAU), "hold": 0.0}
				"wreck":
					fs[id] = {"stage": "clamps", "clamps": [true, true], "out": Vector2.ZERO}
			fs[id]["kind"] = str(f["kind"])
		return fs[id]

	func pressure(f: Dictionary) -> float:
		var st := fstate(f)
		return 0.5 + 0.5 * sin(_t * float(st["w"]) + float(st["ph"])) * (0.85 + 0.15 * sin(_t * 3.7))

	# -- the frame --

	func _process(delta: float) -> void:
		if not is_visible_in_tree() or bay == null or bay.pid == "":
			return
		_t += delta
		var o := bay.op()
		o["lift"] = move_toward(float(o["lift"]), 1.0 if o["open"] else 0.0, delta * 2.5)
		o["shock"] = maxf(0.0, float(o["shock"]) - delta * 1.6)
		o["stress"] = maxf(0.0, float(o["stress"]) - delta * 3.0)
		_flash_t = maxf(0.0, _flash_t - delta)
		# Heat: the welder's, the shocks', a venting leak's; it cools by itself.
		var heat := float(o["heat"])
		var venting := 0
		if o["open"] and bay.powered():
			for f in bay.faults():
				if f["kind"] == "leak":
					venting += 1
		heat += venting * 1.6 * delta
		heat = maxf(0.0, heat - 7.0 * delta)
		if _down and bay.tool == "welder" and o["open"]:
			heat += 13.0 * delta
			if _speed < 6.0:
				_still += delta
				if _still > 0.7:
					heat += 40.0 * delta   # (resting in one place: burning through)
			else:
				_still = 0.0
			_weld(delta)
		o["heat"] = heat
		if heat >= 100.0:
			o["heat"] = 55.0
			_down = false
			# (the hot bead cracks back: half of each weld in progress to do again)
			for f in bay.faults():
				if f["kind"] == "crack" and o["f"].has(int(f["id"])):
					var done: Array = fstate(f)["done"]
					for k in done.size():
						if done[k] and k % 2 == 1:
							done[k] = false
			bay.mishap("Overheated", "The welder cut out and the hot bead cracked back - let it cool.")
		# Held actions.
		if _down and bay.tool == "sealant":
			_seal(delta)
		for k in _spin.keys():
			_spin[k] = float(_spin[k]) - delta * 3.0
			if float(_spin[k]) <= 0.0:
				_spin.erase(k)
		_calibrate(delta)
		if bay.tool == "scanner":
			_scan(delta)
		_since_move += delta
		if _since_move > 0.08:
			_speed = 0.0   # (no movement for a moment: resting)
		if UI.redraw_due(self):
			queue_redraw()
			bay._vitals.queue_redraw()
			_schem_k = (_schem_k + 1) % 4
			if _schem_k == 0:
				bay._schem.queue_redraw()   # (its hurt parts throb: 15 times a second is plenty)

	# -- tools --

	func _scan(delta: float) -> void:
		if not Rect2(Vector2.ZERO, size).has_point(_mouse):
			return
		var o := bay.op()
		var deep: bool = Parts.deep_scan(bay.items_all())
		if not o["open"] and not deep:
			return
		var r := lens_r()
		for f in bay.faults():
			if f.get("found", false) or Parts.FAULTS[f["kind"]]["scan"] != bay.scan:
				continue
			if anchor(f).distance_to(_mouse) <= r:
				var id := int(f["id"])
				o["scan"][id] = float(o["scan"].get(id, 0.0)) + delta
				if float(o["scan"][id]) >= 0.45:
					f["found"] = true
					var comp: Array = Parts.comps(bay.which, bay.pid)[int(f["comp"])]
					Sfx.play("space/scan_done", -6.0)
					bay.log_line("Found: %s in the %s." % [Parts.FAULTS[f["kind"]]["name"].to_lower(), comp[1].to_lower()], "info")
					bay._fill()

	func lens_r() -> float:
		return 105.0 if Parts.deep_scan(bay.items_all()) else 82.0

	## A click on (or near) bolt `i`, whatever tool is in hand: it comes out -
	## or, the casing off, goes back into its hole.
	var _spin := {}   # bolt -> its turn still showing (1 -> 0)
	func _click_bolt(i: int) -> void:
		var o := bay.op()
		var bolts: Array = o["bolts"]
		_spin[i] = 1.0
		if bolts[i] and int(o.get("seized", 0)) > 0:
			# (a warped casing: the bolts bind - a few more turns before one gives)
			o["seized"] = int(o["seized"]) - 1
			Sfx.play("space/select", -14.0)
			bay.log_line("Seized - it binds against the warped casing.", "danger")
			return
		if bolts[i]:
			# Undoing: a neighbour of the last one undone (with more than two left) strains the casing.
			var last := int(o["last_bolt"])
			var left := bolts.count(true)
			if last >= 0 and left > 2 and (absi(i - last) == 1 or absi(i - last) == bolts.size() - 1):
				o["stress"] = float(o["stress"]) + 45.0
				if float(o["stress"]) >= 80.0:
					o["stress"] = 25.0
					o["seized"] = 3
					bay.mishap("The casing warped as it came loose", "The bolts are seized - keep turning.")
				else:
					bay.log_line("The casing creaks - undo the opposite bolt next, not a neighbour.", "danger")
			bolts[i] = false
			o["last_bolt"] = i
			Sfx.play("space/select", -10.0)
			if not bolts.has(true):
				o["open"] = true
				Sfx.play("surface/locker_open", -6.0)
				# What's plainly wrecked shows as soon as you look in.
				var any := false
				for f in bay.faults():
					if f["kind"] == "wreck" and not f.get("found", false):
						f["found"] = true
						any = true
				bay.log_line("Casing off." + (" Something in there is plainly wrecked." if any else ""), "info")
				bay._fill()
		elif o["open"]:
			bolts[i] = true
			Sfx.play("space/select", -10.0)
			if not bolts.has(false):
				o["open"] = false
				o["last_bolt"] = -1
				bay.log_line("Casing closed up.", "info")
				bay._fill()

	func _bolt_at(p: Vector2) -> int:
		var o := bay.op()
		if float(o["lift"]) > 0.05 and float(o["lift"]) < 0.95:
			return -1
		for i in o["bolts"].size():
			if bolt_pos(i).distance_to(p) < BOLT_REACH:
				return i
		return -1

	const BOLT_REACH := 36.0   # (a generous reach round each bolt: a click anywhere near it)

	func _weld(_delta: float) -> void:
		for f in bay.faults():
			if f["kind"] != "crack" or not f.get("found", false):
				continue
			var st := fstate(f)
			var bits := crack_bits(f)
			var done: Array = st["done"]
			for k in bits.size():
				if done[k]:
					continue
				var m: Vector2 = (bits[k][0] + bits[k][1]) * 0.5
				if m.distance_to(_mouse) < 11.0:
					if _speed > 520.0:
						if _flash_t <= 0.0:
							flash("Too fast - the bead doesn't take", Color(1.0, 0.7, 0.3))
						continue
					done[k] = true
					if randf() < 0.25:
						Sfx.play("space/spark", -16.0)
			if not done.has(false):
				bay.fixed(f)
				return

	func _seal(delta: float) -> void:
		for f in bay.faults():
			if f["kind"] != "leak" or not f.get("found", false):
				continue
			if leak_pos(f).distance_to(_mouse) > 34.0:
				continue
			var st := fstate(f)
			var p := pressure(f)
			if p < 0.42:
				st["prog"] = float(st["prog"]) + delta * 0.5
			elif p > 0.68:
				st["prog"] = maxf(0.0, float(st["prog"]) - delta * 0.7)
				if _flash_t <= 0.0:
					flash("Blown away - wait for the pressure to drop", Color(1.0, 0.6, 0.3))
			f["prog"] = st["prog"]
			if float(st["prog"]) >= 1.0:
				bay.fixed(f)
				return

	func _calibrate(delta: float) -> void:
		if bay.tool != "calibrator":
			return
		for f in bay.faults():
			if f["kind"] != "drift" or not f.get("found", false) or not bay.op()["open"]:
				continue
			var st := fstate(f)
			var ok: bool = absf(float(st["f"]) - float(st["f0"])) < 0.07 and absf(angle_difference(float(st["p"]), float(st["p0"]))) < 0.22
			st["hold"] = float(st["hold"]) + delta if ok else 0.0
			if float(st["hold"]) >= 1.0:
				bay.fixed(f)
				return

	## The calibration panel of a drifted component: [scope rect, freq dial, phase dial].
	func cal_panel(f: Dictionary) -> Array:
		# (over the component itself: it's the one being tuned)
		var c := comp_pos(int(f["comp"]))
		var w := Vector2(230, 104)
		var r := Rect2(c + Vector2(-w.x * 0.5, -w.y * 0.5 - 34), w)
		r.position.x = clampf(r.position.x, 4.0, size.x - w.x - 4.0)
		r.position.y = clampf(r.position.y, 4.0, size.y - w.y - 70.0)
		return [r, r.position + Vector2(55, w.y + 30), r.position + Vector2(w.x - 55, w.y + 30)]

	# -- input --

	func _gui_input(event: InputEvent) -> void:
		if bay == null or bay.pid == "":
			return
		var mm := event as InputEventMouseMotion
		if mm:
			var d := mm.position - _mouse
			if _mouse.x > -900:
				_speed = minf(maxf(_speed * 0.6, d.length() / maxf(get_process_delta_time(), 0.004)), 4000.0)
			_since_move = 0.0
			_mouse = mm.position
			if not _drag.is_empty():
				_drag_move(mm)
			if d.length() > 2.0:
				_still = 0.0
			queue_redraw()
			return
		var mb := event as InputEventMouseButton
		if mb == null:
			return
		_mouse = mb.position
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _held_spare >= 0 and mb.pressed:
				_held_spare = wrapi(_held_spare + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1), 0, 4)
				accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _held_spare >= 0:
				_held_spare = wrapi(_held_spare + 1, 0, 4)
			accept_event()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		accept_event()
		if mb.pressed:
			_down = true
			_down_at = mb.position
			_still = 0.0
			var bi := _bolt_at(mb.position)
			if bi >= 0 and (bay.op()["bolts"][bi] or bay.op()["open"]):
				_down = false
				_click_bolt(bi)   # (a bolt: undone / refitted at a click, whatever the tool)
				return
			_press(mb.position)
		else:
			_down = false
			_release(mb.position)
			_drag = {}

	func _press(p: Vector2) -> void:
		var o := bay.op()
		if not o["open"] and bay.tool != "scanner":
			flash("Open the casing first: click its bolts", Color(1.0, 0.8, 0.5))
			return
		match bay.tool:
			"solder":
				for f in bay.faults():
					if f["kind"] != "burn" or not f.get("found", false):
						continue
					var g := burn_geo(f)
					var st := fstate(f)
					for k in 3:
						if not st["joined"][k] and (g["l"][k] as Vector2).distance_to(p) < 13.0:
							_drag = {"kind": "strand", "f": int(f["id"]), "k": k}
							if bay.powered():
								_drag = {}
								bay.shock()
							return
			"calibrator":
				for f in bay.faults():
					if f["kind"] != "drift" or not f.get("found", false):
						continue
					var panel := cal_panel(f)
					for k in 2:
						if (panel[k + 1] as Vector2).distance_to(p) < 26.0:
							_drag = {"kind": "dial", "f": int(f["id"]), "k": k, "y": p.y}
							return
			"forceps":
				_forceps_press(p)

	func _forceps_press(p: Vector2) -> void:
		for f in bay.faults():
			if f["kind"] != "wreck" or not f.get("found", false):
				continue
			var st := fstate(f)
			var c := comp_pos(int(f["comp"]))
			match str(st["stage"]):
				"clamps":
					for k in 2:
						if clamp_pos(f, k).distance_to(p) < 16.0 and st["clamps"][k]:
							st["clamps"][k] = false
							Sfx.play("space/select", -8.0)
							if not st["clamps"].has(true):
								st["stage"] = "lift"
							return
					if c.distance_to(p) < comp_size():
						flash("Open both clamps first", Color(1.0, 0.8, 0.5))
						return
				"lift":
					if c.distance_to(p) < comp_size():
						_drag = {"kind": "wreck", "f": int(f["id"]), "from": p}
						return
				"empty":
					if c.distance_to(p) < comp_size():
						var kind: String = Parts.comps(bay.which, bay.pid)[int(f["comp"])][0]
						if _held_spare < 0:
							var sid: String = Parts.SPARE_OF[kind]
							if bay.count(sid) <= 0:
								flash("No %s - stations sell them" % Items.display_name(sid).to_lower(), Color(1.0, 0.5, 0.4))
								return
							_held_spare = (notch(f) + 1 + randi() % 3) % 4
							Sfx.play("space/pickup", -8.0)
							return
						if _held_spare != notch(f):
							flash("It won't seat - turn it (wheel / right-click)", Color(1.0, 0.75, 0.4))
							Sfx.play("space/select", -4.0)
							return
						var sid2: String = Parts.SPARE_OF[kind]
						if not bay.use_item(sid2):
							_held_spare = -1
							return
						_held_spare = -1
						st["stage"] = "seat"
						st["clamps"] = [false, false]
						Sfx.play("space/dock", -10.0)
						flash("Seated - close the clamps", Color(0.6, 1.0, 0.7))
						return
				"seat":
					for k in 2:
						if clamp_pos(f, k).distance_to(p) < 16.0 and not st["clamps"][k]:
							st["clamps"][k] = true
							Sfx.play("space/select", -8.0)
							if not st["clamps"].has(false):
								bay.fixed(f)
							return

	func _drag_move(mm: InputEventMouseMotion) -> void:
		var f := bay.fault(int(_drag.get("f", -1)))
		if f.is_empty():
			_drag = {}
			return
		match str(_drag["kind"]):
			"dial":
				var st := fstate(f)
				var dy := -mm.relative.y
				if int(_drag["k"]) == 0:
					st["f"] = clampf(float(st["f"]) + dy * 0.008, 0.5, 4.0)
				else:
					st["p"] = wrapf(float(st["p"]) + dy * 0.02, 0.0, TAU)
			"wreck":
				var st2 := fstate(f)
				st2["out"] = _mouse - comp_pos(int(f["comp"]))
				if (st2["out"] as Vector2).length() > comp_size() * 2.6:
					st2["stage"] = "empty"
					st2["out"] = Vector2.ZERO
					_drag = {}
					Sfx.play("space/rock_break", -10.0)
					flash("Out. Click the socket to take a spare", Color(0.8, 0.9, 1.0))

	func _release(p: Vector2) -> void:
		if _drag.is_empty():
			return
		var f := bay.fault(int(_drag.get("f", -1)))
		if f.is_empty():
			return
		match str(_drag["kind"]):
			"strand":
				var g := burn_geo(f)
				var st := fstate(f)
				var k := int(_drag["k"])
				for j in 3:
					if (g["r"][j] as Vector2).distance_to(p) < 15.0:
						if int(g["order"][j]) == k:
							st["joined"][k] = true
							Sfx.play("space/spark", -10.0)
							if not st["joined"].has(false):
								bay.fixed(f)
						else:
							var o := bay.op()
							o["heat"] = minf(100.0, float(o["heat"]) + 22.0)
							Sfx.play("space/hazard_zap", -8.0)
							flash("Wrong terminal - it shorted (heat)", Color(1.0, 0.5, 0.35))
						return
			"wreck":
				var st2 := fstate(f)
				st2["out"] = Vector2.ZERO

	# -- drawing --

	func _draw() -> void:
		if bay == null or bay.pid == "":
			return
		var o := bay.op()
		var a := area()
		# The table: a steel tray with a dark mat, a faint grid, the lamp's pool of light.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.04, 0.05))
		RepairArt.table(self, a)   # (its mat's grid is printed on it)
		draw_texture_rect(_lamp(), Rect2(a.get_center() - a.size * 0.6, a.size * 1.2), false, Color(1.0, 0.92, 0.8, 0.16))
		var lift := float(o["lift"])
		if lift > 0.0:
			_draw_inside()
		if bay.tool == "scanner":
			_draw_scan()
		if lift < 1.0:
			_draw_casing(lift)
		_draw_tool()
		if _flash_t > 0.0:
			var f := ThemeDB.fallback_font
			var at := _flash_at + Vector2(16, -18)
			at.x = clampf(at.x, 6, size.x - 420)
			at.y = clampf(at.y, 24, size.y - 8)
			draw_string_outline(f, at, _flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 5, Color(0, 0, 0, minf(1.0, _flash_t)))
			draw_string(f, at, _flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(_flash_col, minf(1.0, _flash_t)))

	func _draw_inside() -> void:
		var s := comp_size()
		var cs := Parts.comps(bay.which, bay.pid)
		var by_comp := {}
		for f in bay.faults():
			by_comp[int(f["comp"])] = by_comp.get(int(f["comp"]), []) + [f]
		var live: bool = bay.powered()
		# Cables (a burnt one is drawn with its gap).
		for i in cs.size():
			var ab := cable(i)
			var burnt := {}
			for f in by_comp.get(i, []):
				if f["kind"] == "burn":
					burnt = f
			var col := Color(0.95, 0.7, 0.3, 0.9) if live else Color(0.45, 0.42, 0.4)
			if burnt.is_empty():
				_cable(ab[0], ab[1], col)
				if live:
					var t := fmod(_t * 0.6 + i * 0.27, 1.0)
					var at := (ab[0] as Vector2).lerp(ab[1], t)
					draw_circle(at, 6.0, Color(1.0, 0.8, 0.4, 0.25))
					draw_circle(at, 2.5, Color(1.0, 0.95, 0.75))
			else:
				_draw_burn(burnt, col)
		# Components.
		for i in cs.size():
			var c := comp_pos(i)
			var wreck := {}
			for f in by_comp.get(i, []):
				if f["kind"] == "wreck":
					wreck = f
			if wreck.is_empty():
				RepairArt.socket(self, c, s)
				# Alive while the power's on and nothing's wrong with it: the
				# servo hunting a little, lights and glows (RepairArt.live).
				var well: bool = live and not by_comp.has(i)
				RepairArt.component(self, cs[i][0], c, s, Color.WHITE, false, 0.06 * sin(_t * 1.7 + i * 2.1) if well and cs[i][0] == "servo" else 0.0)
				if well:
					RepairArt.live(self, cs[i][0], c, s, _t, i)
			else:
				_draw_wreck(wreck, cs[i][0], c, s)
			var font := ThemeDB.fallback_font
			var name_w := font.get_string_size(cs[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var lab := c + Vector2(-name_w * 0.5, s * 1.2 + 18)
			draw_rect(Rect2(lab + Vector2(-6, -14), Vector2(name_w + 12, 19)), Color(0.02, 0.025, 0.03, 0.75))   # (a label plate)
			draw_rect(Rect2(lab + Vector2(-6, -14), Vector2(name_w + 12, 19)), Color(1.0, 0.6, 0.25, 0.35), false, 1.0)
			draw_string(font, lab, cs[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.88, 0.82))
		# Found faults.
		for f in bay.faults():
			if not f.get("found", false):
				continue
			match str(f["kind"]):
				"crack":
					_draw_crack(f)
				"leak":
					_draw_leak(f)
				"drift":
					_draw_drift(f)

	func _draw_crack(f: Dictionary) -> void:
		var st := fstate(f)
		var bits := crack_bits(f)
		for k in bits.size():
			var a: Vector2 = bits[k][0]
			var b: Vector2 = bits[k][1]
			var n := (b - a).normalized().orthogonal()
			if st["done"][k]:
				# A weld bead: a ridge of bright metal, rippled, still warm near the torch.
				draw_line(a, b, Color(0.05, 0.05, 0.06, 0.8), 8.0, true)
				draw_line(a, b, Color(0.62, 0.63, 0.68), 6.0, true)
				draw_line(a - n * 1.3, b - n * 1.3, Color(0.95, 0.96, 1.0, 0.85), 1.6, true)
				draw_line(a + n * 1.8, b + n * 1.8, Color(0.25, 0.26, 0.3, 0.7), 1.2, true)
				var m := a.lerp(b, 0.5)
				draw_line(m - n * 2.6, m + n * 2.6, Color(0.2, 0.2, 0.24, 0.5), 1.0, true)
				var near := m.distance_to(_mouse)
				if _down and bay.tool == "welder" and near < 60.0:
					draw_line(a, b, Color(1.0, 0.6, 0.2, 0.75 * (1.0 - near / 60.0)), 5.0, true)
			else:
				# The crack: a dark fissure with depth - shadow, the gap, a lit lip.
				draw_line(a, b, Color(0, 0, 0, 0.3), 8.0, true)
				draw_line(a, b, Color(0, 0, 0, 0.97), 3.5, true)
				draw_line(a + n * 2.2, b + n * 2.2, Color(1, 1, 1, 0.22), 1.0, true)
				draw_line(a, b, Color(1.0, 0.45, 0.2, 0.18 + 0.12 * sin(_t * 4.0 + k * 0.6)), 1.2, true)

	func _draw_burn(f: Dictionary, col: Color) -> void:
		var g := burn_geo(f)
		var st := fstate(f)
		var found: bool = f.get("found", false)
		var dn := ((g["b"] - g["a"]) as Vector2).normalized()
		# The scorch: soot spread round the gap, streaked along the cable.
		RepairArt.glow(self, g["mid"], 58.0, Color(0.02, 0.012, 0.008, 0.85))
		RepairArt.glow(self, (g["mid"] as Vector2) + dn * 22.0, 34.0, Color(0.02, 0.012, 0.008, 0.6))
		RepairArt.glow(self, (g["mid"] as Vector2) - dn * 22.0, 34.0, Color(0.02, 0.012, 0.008, 0.6))
		if bay.powered() and st["joined"].has(false):
			RepairArt.glow(self, g["mid"], 26.0, Color(1.0, 0.5, 0.15, 0.12 + 0.1 * sin(_t * 9.0)))   # (still arcing inside)
		_cable(g["a"], (g["mid"] as Vector2) - dn * 40.0, col, true)
		_cable((g["mid"] as Vector2) + dn * 40.0, g["b"], col, true)
		if not found:
			return
		for k in 3:
			var cl: Color = g["cols"][k]
			var lp: Vector2 = g["l"][k]
			if st["joined"][k]:
				var j: int = g["order"].find(k)
				_strand(lp, g["r"][j], cl)
				draw_circle(g["r"][j], 5.0, Color(0.75, 0.76, 0.72))   # (a bead of solder)
				draw_circle(g["r"][j] + Vector2(-1.5, -1.5), 2.0, Color(1, 1, 1, 0.8))
			else:
				# A frayed strand end: its insulation, the copper showing.
				draw_circle(lp, 6.5, cl.darkened(0.45))
				draw_circle(lp, 5.0, cl)
				draw_circle(lp + Vector2(-1.5, -1.5), 1.8, cl.lightened(0.5))
				for w in 3:
					draw_line(lp, lp + dn.rotated((w - 1) * 0.5) * 9.0, Color(0.95, 0.55, 0.3), 1.2, true)
		for j in 3:
			var rp: Vector2 = g["r"][j]
			var jc: Color = g["cols"][g["order"][j]]
			draw_rect(Rect2(rp - Vector2(8, 8), Vector2(16, 16)), Color(0.08, 0.085, 0.1))
			draw_rect(Rect2(rp - Vector2(7, 7), Vector2(14, 14)), Color(0.24, 0.25, 0.28))
			draw_rect(Rect2(rp - Vector2(7, 7), Vector2(14, 14)), jc, false, 2.0)
			draw_circle(rp, 3.0, Color(0.85, 0.65, 0.3))   # (the terminal's brass)
		if bay.powered() and int(_t * 7.0) % 3 == 0:
			var m: Vector2 = g["mid"]
			draw_line(m + Vector2(-8, -6), m + Vector2(3, 2), Color(1.0, 1.0, 0.7), 2.0)
			draw_line(m + Vector2(3, 2), m + Vector2(-2, 9), Color(1.0, 1.0, 0.7), 2.0)
		if _drag.get("kind", "") == "strand" and int(_drag["f"]) == int(f["id"]):
			var k2 := int(_drag["k"])
			_strand(g["l"][k2], _mouse, g["cols"][k2])

	func _draw_leak(f: Dictionary) -> void:
		var p := leak_pos(f)
		var st := fstate(f)
		var pr := pressure(f)
		var prog := float(st["prog"])
		# The jet: longer with the pressure, shorter as it's sealed.
		var dir := (p - comp_pos(int(f["comp"]))).normalized()
		var reach := (30.0 + 70.0 * pr) * (1.0 - prog)
		for k in 9:   # puffs of vapour blown out along the jet, widening and thinning
			var u := fmod(_t * (1.2 + 1.6 * pr) + k / 9.0, 1.0)
			var side := dir.orthogonal() * sin(k * 2.4 + _t * 3.0) * u * 9.0
			RepairArt.glow(self, p + dir * reach * u + side, 5.0 + 15.0 * u, Color(0.8, 0.93, 1.0, 0.5 * (1.0 - u) * (1.0 - prog)))
		for k in 3:
			var spread := dir.rotated((k - 1) * 0.12)
			draw_line(p, p + spread * reach * 0.45, Color(0.9, 0.97, 1.0, 0.5 * (1.0 - prog)), 1.5, true)
		RepairArt.glow(self, p, 20.0, Color(0.7, 0.9, 1.0, 0.25 * (1.0 - prog)))   # (frost round the hole)
		draw_circle(p, 8.0, Color(0.04, 0.05, 0.06))
		draw_circle(p, 5.0, Color(0.55, 0.8, 1.0, 0.6 * (1.0 - prog)))
		draw_arc(p, 7.0 + prog * 8.0, 0, TAU, 18, Color(0.9, 0.92, 0.7), 3.0 * prog + 0.5, true)   # (the sealant bead)
		# The gauge beside it.
		var g := p + Vector2(50, -50)
		RepairArt.gauge(self, g, 22.0)
		draw_arc(g, 17.0, PI * 0.75, PI * 0.75 + PI * 1.5 * 0.42, 14, Color(0.4, 1.0, 0.5, 0.9), 4.0, true)
		draw_arc(g, 17.0, PI * 0.75 + PI * 1.5 * 0.68, PI * 2.25, 10, Color(1.0, 0.35, 0.3, 0.9), 4.0, true)
		var ang := PI * 0.75 + PI * 1.5 * pr
		draw_line(g, g + Vector2.from_angle(ang) * 18.0, Color(1.0, 0.55, 0.3), 2.5, true)
		draw_circle(g, 3.5, Color(0.8, 0.82, 0.86))
		draw_arc(g, 14.0, -2.6, -1.9, 6, Color(1, 1, 1, 0.25), 2.0, true)   # (a glint on the glass)

	func _draw_drift(f: Dictionary) -> void:
		var c := comp_pos(int(f["comp"]))
		var s := comp_size()
		var st := fstate(f)
		for k in 3:
			var r := s * (1.05 + 0.18 * k) + 4.0 * sin(_t * float(st["f"]) * 4.0 + k)
			draw_arc(c, r, 0, TAU, 32, Color(0.45, 1.0, 0.6, 0.45 - k * 0.12), 1.5, true)
		if bay.tool != "calibrator":
			return
		var panel := cal_panel(f)
		var r2: Rect2 = panel[0]
		draw_rect(r2.grow(4), Color(0.16, 0.17, 0.2, 0.97))
		draw_rect(r2.grow(4), Color(0.4, 0.42, 0.46), false, 1.5)
		draw_rect(r2, Color(0.01, 0.05, 0.03, 0.97))
		for gx in 7:
			var xx2 := r2.position.x + r2.size.x * (gx + 1) / 8.0
			draw_line(Vector2(xx2, r2.position.y), Vector2(xx2, r2.end.y), Color(0.45, 1.0, 0.6, 0.08), 1.0)
		draw_line(Vector2(r2.position.x, r2.get_center().y), Vector2(r2.end.x, r2.get_center().y), Color(0.45, 1.0, 0.6, 0.12), 1.0)
		draw_rect(r2, Color(0.45, 1.0, 0.6, 0.6), false, 1.0)
		var ref := PackedVector2Array()
		var cur := PackedVector2Array()
		for i in 61:
			var u := i / 60.0
			var xx := r2.position.x + 6 + u * (r2.size.x - 12)
			ref.append(Vector2(xx, r2.get_center().y + sin(u * TAU * float(st["f0"]) + float(st["p0"])) * r2.size.y * 0.32))
			cur.append(Vector2(xx, r2.get_center().y + sin(u * TAU * float(st["f"]) + float(st["p"])) * r2.size.y * 0.32))
		draw_polyline(ref, Color(1, 1, 1, 0.35), 2.0, true)
		var good := float(st["hold"]) > 0.0
		draw_polyline(cur, Color(0.4, 1.0, 0.55) if good else Color(1.0, 0.75, 0.3), 2.0, true)
		if good:
			draw_rect(Rect2(r2.position + Vector2(0, r2.size.y - 4), Vector2(r2.size.x * float(st["hold"]), 4)), Color(0.4, 1.0, 0.55))
		var font := ThemeDB.fallback_font
		for k in 2:
			var dc: Vector2 = panel[k + 1]
			var v: float = (float(st["f"]) - 0.5) / 3.5 * TAU * 0.8 if k == 0 else float(st["p"])
			draw_arc(dc, 27.0, 0, TAU, 32, Color(0.45, 1.0, 0.6, 0.55), 2.0, true)
			RepairArt.knob(self, dc, 24.0)
			var tipv := dc + Vector2.from_angle(v - PI * 0.5) * 21.0
			draw_line(dc + Vector2.from_angle(v - PI * 0.5) * 8.0, tipv, Color(0.45, 1.0, 0.6), 3.0, true)
			draw_circle(tipv, 2.5, Color(0.8, 1.0, 0.85))
			var lbl := "FREQ" if k == 0 else "PHASE"
			draw_string(font, dc + Vector2(-18, 40), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.9, 0.75))

	func _draw_wreck(f: Dictionary, kind: String, c: Vector2, s: float) -> void:
		var found: bool = f.get("found", false)
		var st := fstate(f) if found else {"stage": "clamps", "clamps": [true, true], "out": Vector2.ZERO}
		var stage := str(st["stage"])
		# The socket (and its notch: the way a new part must face).
		RepairArt.empty_socket(self, c, s)
		var nd := Vector2.from_angle(notch(f) * PI * 0.5 - PI * 0.5)
		_notch_mark(c + nd * s * 1.05, nd, Color(1.0, 0.6, 0.25))
		match stage:
			"clamps", "lift":
				RepairArt.component(self, kind, c + (st["out"] as Vector2), s, Color.WHITE, true)
				for k in 4:   # smoke curling up off it
					var u := fmod(_t * 0.35 + k * 0.25, 1.0)
					var at := c + (st["out"] as Vector2) + Vector2(s * 0.25 + sin(_t * 1.3 + k * 2.0) * s * 0.12 * u, -s * 0.2 - u * s * 1.0)
					RepairArt.glow(self, at, s * (0.14 + 0.3 * u), Color(0.22, 0.2, 0.19, 0.5 * sin(u * PI)))
				RepairArt.glow(self, c + (st["out"] as Vector2), s * 0.9, Color(1.0, 0.35, 0.08, 0.07 + 0.05 * sin(_t * 2.3)))   # (its embers' glow)
			"seat":
				RepairArt.component(self, kind, c, s, Color.WHITE, false, notch(f) * PI * 0.5)
		if stage in ["clamps", "seat"]:
			for k in 2:
				var cp := clamp_pos(f, k)
				var shut: bool = st["clamps"][k]
				if found and bay.tool == "forceps" and shut:
					draw_circle(cp, 24.0, Color(1.0, 0.6, 0.25, 0.18 + 0.1 * sin(_t * 5.0)))
				RepairArt.clamp_(self, cp, shut)

	func _draw_scan() -> void:
		if _mouse.x < -900:
			return
		var o := bay.op()
		var deep: bool = Parts.deep_scan(bay.items_all())
		var col: Color = Parts.SCANS[bay.scan]["color"]
		var r := lens_r()
		# The lens: tinted glass in a ticked bezel, a line sweeping down it.
		draw_circle(_mouse, r, Color(col, 0.07))
		RepairArt.glow(self, _mouse, r * 1.05, Color(col, 0.1))
		draw_arc(_mouse, r + 3.0, 0, TAU, 56, Color(0.05, 0.06, 0.08, 0.9), 7.0, true)
		draw_arc(_mouse, r + 3.0, 0, TAU, 56, Color(0.55, 0.58, 0.64), 3.0, true)
		draw_arc(_mouse, r, 0, TAU, 56, Color(col, 0.85), 1.5, true)
		for k in 24:
			var ta := TAU * k / 24.0
			var t1 := 7.0 if k % 6 == 0 else 3.5
			draw_line(_mouse + Vector2.from_angle(ta) * (r - t1), _mouse + Vector2.from_angle(ta) * (r - 0.5), Color(col, 0.7), 1.0, true)
		draw_arc(_mouse, r + 8.0, _t * 2.0, _t * 2.0 + 0.8, 10, Color(col, 0.9), 2.5, true)
		draw_arc(_mouse, r + 8.0, _t * 2.0 + PI, _t * 2.0 + PI + 0.8, 10, Color(col, 0.45), 2.5, true)
		var sy := (fmod(_t * 0.6, 1.0) * 2.0 - 1.0) * r * 0.96
		var half := sqrt(maxf(0.0, r * r - sy * sy))
		draw_line(_mouse + Vector2(-half, sy), _mouse + Vector2(half, sy), Color(col, 0.35), 1.5)
		draw_line(_mouse + Vector2(-half, sy - 3.0), _mouse + Vector2(half, sy - 3.0), Color(col, 0.12), 3.0)
		for d4 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			draw_line(_mouse + d4 * r * 0.18, _mouse + d4 * r * 0.4, Color(col, 0.35), 1.0)
		draw_arc(_mouse, r * 0.7, -2.5, -1.9, 8, Color(1, 1, 1, 0.12), 3.0, true)   # (a glint on the glass)
		if not o["open"] and not deep:
			draw_string(ThemeDB.fallback_font, _mouse + Vector2(-r * 0.8, 4), "casing blocks the scan", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(col, 0.9))
			return
		# What this mode sees under the lens.
		for f in bay.faults():
			if Parts.FAULTS[f["kind"]]["scan"] != bay.scan:
				continue
			var at := anchor(f)
			var d := at.distance_to(_mouse)
			if d > r:
				continue
			var k := 1.0 - d / r
			var prog := clampf(float(o["scan"].get(int(f["id"]), 0.0)) / 0.45, 0.0, 1.0)
			match bay.scan:
				"structure":
					if f["kind"] == "crack":
						draw_polyline(crack_pts(f), Color(col, 0.9 * k + 0.1), 2.5, true)
					else:
						draw_circle(at, comp_size() * 0.9, Color(col, 0.35 * k))
				"thermal":
					for i in 4:
						draw_circle(at + Vector2(0, -i * 9.0 - fmod(_t * 30.0, 9.0)), 10.0 + i * 4.0, Color(0.3, 0.6, 1.0, 0.28 * k))
				"field":
					draw_circle(at, 18.0, Color(0.05, 0.0, 0.1, 0.8 * k))
					draw_arc(at, 22.0, _t * 6.0, _t * 6.0 + 1.2, 6, Color(col, k), 2.0)
				"resonance":
					for i in 3:
						draw_arc(at, 12.0 + fmod(_t * 40.0 + i * 14.0, 42.0), 0, TAU, 24, Color(col, 0.6 * k), 1.5, true)
			if not f.get("found", false):
				draw_arc(at, 30.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 24, Color(1, 1, 1, 0.9), 3.0, true)

	func _draw_casing(lift: float) -> void:
		var o := bay.op()
		var r := casing()
		var off := Vector2(0, -lift * r.size.y * 0.8)
		var alpha := 1.0 - lift
		var rr := Rect2(r.position + off, r.size)
		RepairArt.lid(self, rr, Color(1, 1, 1, alpha))
		# The part's name stencilled on the casing, and its stress cracks.
		var font := ThemeDB.fallback_font
		var name: String = Parts.info(bay.which, bay.pid)["name"].to_upper()
		var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		draw_string(font, rr.get_center() + Vector2(-w * 0.5 + 1.5, 11.5), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.18 * alpha))   # (stencilled: a lit lower edge)
		draw_string(font, rr.get_center() + Vector2(-w * 0.5, 10), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.1, 0.11, 0.13, 0.85 * alpha))
		var stress := float(o["stress"])
		if stress > 0.0:
			draw_rect(rr, Color(1.0, 0.3, 0.2, stress / 100.0 * 0.5 * alpha), false, 6.0)
		for i in o["bolts"].size():
			var bp := bolt_pos(i) + off
			var turning := float(_spin.get(i, 0.0)) * 6.0
			RepairArt.bolt(self, bp, 13.0, not o["bolts"][i], turning)
			if o["bolts"][i] and lift <= 0.0 and bolt_pos(i).distance_to(_mouse) < BOLT_REACH:
				draw_arc(bp, 22.0, 0, TAU, 24, Color(1.0, 0.75, 0.3, 0.9), 2.5, true)   # (under the mouse: a click undoes it)
		if lift <= 0.0 and not Parts.deep_scan(bay.items_all()):
			var known: int = bay.faults().filter(func(f): return f.get("found", false)).size()
			var hidden: int = bay.faults().size() - known
			if hidden > 0 or known > 0:
				var txt := "%d fault%s found%s" % [known, "s" if known != 1 else "", (" - untraced damage inside" if hidden > 0 else "")]
				var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				draw_string_outline(font, rr.get_center() + Vector2(-tw * 0.5, 44), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.6 * alpha))
				draw_string(font, rr.get_center() + Vector2(-tw * 0.5, 44), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.7, 0.4, alpha))
		if o["open"]:
			return
		# Open: the empty holes stay round the edge to refit the bolts into.

	func _draw_tool() -> void:
		var o := bay.op()
		if o["open"]:
			# Bolt holes round the edge while the casing's off (to refit).
			for i in o["bolts"].size():
				RepairArt.bolt(self, bolt_pos(i), 13.0, not o["bolts"][i], float(_spin.get(i, 0.0)) * 6.0)
				if bolt_pos(i).distance_to(_mouse) < BOLT_REACH:
					draw_arc(bolt_pos(i), 22.0, 0, TAU, 24, Color(1.0, 0.75, 0.3, 0.9), 2.5, true)   # (a click refits / undoes it)
		if _mouse.x < -900:
			return
		var m := _mouse
		match bay.tool:
			"welder":
				var hot: bool = _down and o["open"]
				RepairArt.tool(self, "welder", m)
				if hot:
					draw_circle(m, 22.0, Color(1.0, 0.6, 0.25, 0.18))
					draw_circle(m, 11.0 + randf() * 3.0, Color(1.0, 0.8, 0.45, 0.45))
					draw_circle(m, 5.0, Color(1.0, 1.0, 0.9))
					for k in 3:   # sparks
						var sd := Vector2.from_angle(randf() * TAU)
						draw_line(m + sd * 6.0, m + sd * randf_range(14.0, 26.0), Color(1.0, 0.85, 0.4), 1.5, true)
				else:
					draw_circle(m, 3.0, Color(0.9, 0.55, 0.3, 0.8))
			"solder":
				RepairArt.tool(self, "solder", m)
				draw_circle(m, 2.5, Color(0.9, 0.9, 0.85))
			"sealant":
				RepairArt.tool(self, "sealant", m)
				if _down:
					draw_circle(m, 10.0, Color(0.85, 0.95, 1.0, 0.35))
					draw_circle(m, 5.0, Color(0.95, 1.0, 1.0, 0.6))
			"calibrator":
				draw_arc(m, 10.0, 0, TAU, 16, Color(0.45, 1.0, 0.6), 2.0, true)
			"forceps":
				if _held_spare < 0:
					RepairArt.tool(self, "forceps", m)
				if _held_spare >= 0:
					var f := _wreck_on_table()
					if not f.is_empty():
						var kind: String = Parts.comps(bay.which, bay.pid)[int(f["comp"])][0]
						RepairArt.component(self, kind, m, comp_size(), Color(1, 1, 1, 0.85), false, _held_spare * PI * 0.5)
						var nd := Vector2.from_angle(_held_spare * PI * 0.5 - PI * 0.5)
						_notch_mark(m + nd * comp_size() * 1.05, nd, Color(1.0, 0.6, 0.25, 0.9))
						RepairArt.tool(self, "forceps", m + Vector2(-6, -6))

	## An insulated cable: its shadow, the sheath, a highlight along it, plugs at its ends.
	func _cable(a: Vector2, b: Vector2, col: Color, cut_end := false) -> void:
		var d := (b - a).normalized()
		var n := d.orthogonal()
		draw_line(a + Vector2(3, 4), b + Vector2(3, 4), Color(0, 0, 0, 0.35), 10.0, true)
		draw_line(a, b, Color(0.07, 0.07, 0.08), 10.0, true)
		draw_line(a, b, col.darkened(0.35), 6.0, true)
		draw_line(a - n * 1.5, b - n * 1.5, col.lightened(0.25), 2.0, true)
		for e in ([a] if cut_end else [a, b]):
			draw_circle(e, 7.5, Color(0.1, 0.1, 0.12))
			draw_circle(e, 6.0, Color(0.62, 0.64, 0.68))
			draw_circle(e + Vector2(-1.5, -1.5), 2.5, Color(0.9, 0.92, 0.95))

	## A soldered strand (or one being drawn across).
	func _strand(a: Vector2, b: Vector2, col: Color) -> void:
		draw_line(a + Vector2(2, 3), b + Vector2(2, 3), Color(0, 0, 0, 0.35), 5.0, true)
		draw_line(a, b, col.darkened(0.4), 5.0, true)
		draw_line(a, b, col, 3.0, true)
		draw_line(a, b, col.lightened(0.45), 1.0, true)

	## The notch marking the way a part must face: a small arrow pointing out.
	func _notch_mark(at: Vector2, out: Vector2, col: Color) -> void:
		var side := out.orthogonal()
		var tri := PackedVector2Array([at + out * 10.0, at - out * 4.0 + side * 8.0, at - out * 4.0 - side * 8.0])
		draw_colored_polygon(tri, Color(0, 0, 0, 0.6))
		var inner := PackedVector2Array([at + out * 7.0, at - out * 2.0 + side * 5.5, at - out * 2.0 - side * 5.5])
		draw_colored_polygon(inner, col)

	## The lamp's pool of light (a radial gradient, made once).
	static var _lamp_tex: GradientTexture2D

	static func _lamp() -> GradientTexture2D:
		if _lamp_tex == null:
			var g := Gradient.new()
			g.set_color(0, Color(1, 1, 1, 1))
			g.set_color(1, Color(1, 1, 1, 0))
			g.add_point(0.5, Color(1, 1, 1, 0.35))
			_lamp_tex = GradientTexture2D.new()
			_lamp_tex.gradient = g
			_lamp_tex.fill = GradientTexture2D.FILL_RADIAL
			_lamp_tex.fill_from = Vector2(0.5, 0.5)
			_lamp_tex.fill_to = Vector2(1.0, 0.5)
			_lamp_tex.width = 256
			_lamp_tex.height = 256
		return _lamp_tex

	func _wreck_on_table() -> Dictionary:
		for f in bay.faults():
			if f["kind"] == "wreck" and f.get("found", false) and str(fstate(f)["stage"]) == "empty":
				return f
		return {}


# --- The schematic and the vitals ------------------------------------------------------------

class Schematic extends Control:
	var bay: RepairBay

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_STOP

	func _xf() -> Transform2D:
		var s := minf(size.x, size.y) * 0.46
		return Transform2D(0.0, Vector2(s, s), 0.0, size * 0.5)

	func _shape(pid: String) -> PackedVector2Array:
		var out := PackedVector2Array()
		var xf := _xf()
		if bay.which == "automaton":
			# The box round the part's structures on the body (standing: its head up).
			var r := Rect2()
			var first := true
			for c in Parts.comps(bay.which, pid):
				var p := _body(float(c[3]), float(c[4]))
				r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
				first = false
			r = r.grow(0.075)
			for p in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
				out.append(xf * p)
			return out
		for p in Parts.info(bay.which, pid)["shape"]:
			out.append(xf * Vector2(p[0], p[1]))
		return out

	## The automaton's body (metres: x across, z up - AnatomyArt) in the schematic's -1..1 box, standing.
	const BODY_HALF := 0.975   # (half the picture's length, in metres)
	func _body(x: float, z: float) -> Vector2:
		return Vector2(x / BODY_HALF, (0.845 - z) / BODY_HALF)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# The smallest shape under the click (the reactor inside the plating).
			var best := ""
			var best_a := INF
			for pid in Parts.BODIES[bay.which]["parts"]:
				var poly := _shape(pid)
				if Geometry2D.is_point_in_polygon(mb.position, poly):
					var r := Rect2(poly[0], Vector2.ZERO)
					for p in poly:
						r = r.expand(p)
					if r.get_area() < best_a:
						best_a = r.get_area()
						best = pid
			if best != "":
				bay.pick_part(best)
			accept_event()

	func _draw() -> void:
		if bay == null:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.07))
		for i in 9:
			draw_line(Vector2(0, size.y * i / 8.0), Vector2(size.x, size.y * i / 8.0), Color(0.4, 0.7, 1.0, 0.06), 1.0)
			draw_line(Vector2(size.x * i / 8.0, 0), Vector2(size.x * i / 8.0, size.y), Color(0.4, 0.7, 1.0, 0.06), 1.0)
		if bay.which == "automaton":
			# Its anatomy, standing (the picture lies head-left: turned a quarter).
			var at: Texture2D = AnatomyArt.tex("muscles" if bay.layer == "muscles" else "skeleton")
			if at:
				var ln := minf(size.x, size.y) * 0.92
				draw_set_transform(size * 0.5, PI * 0.5, Vector2.ONE)
				draw_texture_rect(at, Rect2(-ln * 0.5, -ln * 0.5 * AnatomyArt.SIZE.y / AnatomyArt.SIZE.x, ln, ln * AnatomyArt.SIZE.y / AnatomyArt.SIZE.x), false, Color(1, 1, 1, 0.55))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var tex := _picture()
		if tex:
			var ts := Vector2(tex.get_size())
			var k := minf(size.x, size.y) * 0.92 / maxf(ts.x, ts.y)
			draw_texture_rect(tex, Rect2(size * 0.5 - ts * k * 0.5, ts * k), false, Color(1, 1, 1, 0.35))
		var c := bay.cond()
		var order: Array = Parts.BODIES[bay.which]["parts"].keys()
		# Big shapes first (the plating behind the reactor).
		order.sort_custom(func(a, b): return _area(a) > _area(b))
		var font := ThemeDB.fallback_font
		for pid in order:
			var poly := _shape(pid)
			var h := Parts.working(c, bay.which, pid)
			var col := Color(0.35, 1.0, 0.55).lerp(Color(1.0, 0.3, 0.2), 1.0 - h)
			# (A hurt part's fill throbs; the one on the table wears a bright rim with a glow under it.)
			var throb := 0.07 * sin(Time.get_ticks_msec() / 1000.0 * 3.0) * (1.0 - h) if h < 0.999 else 0.0
			var dim := 0.45 if bay.which == "automaton" else 1.0   # (its anatomy shows through)
			draw_colored_polygon(poly, Color(col, ((0.16 if pid != bay.pid else 0.34) + throb) * dim))
			var closed := poly.duplicate()
			closed.append(poly[0])
			if pid == bay.pid:
				draw_polyline(closed, Color(1.0, 0.7, 0.3, 0.25), 8.0, true)
			draw_polyline(closed, Color(0, 0, 0, 0.5), 3.5 if pid != bay.pid else 5.0, true)
			draw_polyline(closed, Color(col, 0.85) if pid != bay.pid else Color(1.0, 0.82, 0.45), 1.5 if pid != bay.pid else 2.5, true)
			var fs: Array = Parts.part(c, bay.which, pid)["faults"]
			if fs.any(func(f): return not f.get("found", false)):
				var ctr := Vector2.ZERO
				for p in poly:
					ctr += p
				ctr /= poly.size()
				draw_string(font, ctr + Vector2(-5, 6), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.75, 0.35))
		draw_string(font, Vector2(8, size.y - 8), "click a part to put it on the table", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.75, 0.9, 0.7))

	## The ship's own picture (nose up), behind its parts.
	func _picture() -> Texture2D:
		if bay.which != "ship" or bay.ship == null or bay.ship.get("sprite") == null:
			return null
		return (bay.ship.sprite as Sprite2D).texture

	func _area(pid: String) -> float:
		var poly := _shape(pid)
		var r := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			r = r.expand(p)
		return r.get_area()


class Vitals extends Control:
	var bay: RepairBay
	var _trace := PackedFloat32Array()
	var _t := 0.0
	var _beat := 0.0

	func _process(delta: float) -> void:
		if not is_visible_in_tree() or bay == null or bay.pid == "":
			return
		var o := bay.op()
		var heat := float(o["heat"])
		_t += delta
		var rate := 1.0 + heat / 45.0 + float(o["shock"]) * 2.0
		_beat = fmod(_beat + delta * rate, 1.0)
		var v := 0.0
		if _beat < 0.06:
			v = -1.0
		elif _beat < 0.1:
			v = 0.7
		elif _beat < 0.16:
			v = -0.2
		v += (randf() - 0.5) * (0.06 + float(o["shock"]) * 0.8)
		if not bay.powered() and bay.which != "automaton":
			v = (randf() - 0.5) * 0.03
		_trace.append(v)
		if _trace.size() > 160:
			_trace = _trace.slice(_trace.size() - 160)

	func _draw() -> void:
		if bay == null or bay.pid == "":
			return
		var o := bay.op()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.03))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.9, 0.5, 0.4), false, 1.0)
		var font := ThemeDB.fallback_font
		var heat := float(o["heat"])
		var tr := Rect2(8, 8, size.x - 112, 62)
		var pts := PackedVector2Array()
		for i in _trace.size():
			pts.append(Vector2(tr.position.x + tr.size.x * i / 159.0, tr.get_center().y + _trace[i] * tr.size.y * 0.45))
		var col := Color(0.4, 1.0, 0.55).lerp(Color(1.0, 0.35, 0.25), clampf(heat / 100.0, 0.0, 1.0))
		if pts.size() > 1:
			draw_polyline(pts, col, 1.5, true)
		var bpm := roundi(60.0 * (1.0 + heat / 45.0 + float(o["shock"]) * 2.0)) if bay.powered() or bay.which == "automaton" else 0
		draw_string(font, Vector2(size.x - 94, 24), "%d /min" % bpm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		# Temperature, pressure, integrity bars; the power lamp.
		var leaks: int = bay.faults().filter(func(f): return f["kind"] == "leak").size()
		var rows := [["TEMP", heat / 100.0, Color(1.0, 0.5, 0.25) if heat < 70.0 else Color(1.0, 0.25, 0.2), "%d°" % roundi(20 + heat * 4.0)],
			["PRESS", clampf(1.0 - leaks * 0.22, 0.0, 1.0), Color(0.45, 0.75, 1.0), "%d%%" % roundi(clampf(1.0 - leaks * 0.22, 0.0, 1.0) * 100.0)],
			["WORK", Parts.health(bay.cond(), bay.which, bay.pid), Color(0.45, 1.0, 0.55), "%d%%" % roundi(Parts.health(bay.cond(), bay.which, bay.pid) * 100.0)]]
		for i in rows.size():
			var y := 82.0 + i * 20.0
			draw_string(font, Vector2(8, y + 12), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.75))
			var br := Rect2(62, y + 2, size.x - 140, 12)
			draw_rect(br, Color(0.1, 0.12, 0.12))
			draw_rect(Rect2(br.position, Vector2(br.size.x * clampf(rows[i][1], 0.0, 1.0), br.size.y)), rows[i][2])
			draw_string(font, Vector2(size.x - 70, y + 12), rows[i][3], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.9, 0.85))
		var on: bool = bay.powered()
		draw_string(font, Vector2(size.x - 94, 56), "FEELS" if bay.which == "automaton" else "POWER", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.75))
		draw_circle(Vector2(size.x - 24, 51), 7.0, Color(0.4, 1.0, 0.5) if on else Color(0.35, 0.1, 0.1))


class SpareIcon extends Control:
	var kind := "circuit"

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _draw() -> void:
		RepairArt.component(self, kind, size * 0.5, minf(size.x, size.y) * 0.4)
