extends Node
## Every rebindable control (autoload "Keybinds"): its default keys and
## gamepad button, the player's own choices (Settings > Controls, saved in
## user://keybinds.cfg), all registered in Godot's InputMap so the game asks
## `Keybinds.pressed(event, "dock")` instead of naming a key.
##
## Each action has three slots: two keys and one gamepad input ("" = none).
## A slot is written "k:<key name>" (OS.get_keycode_string - with its
## modifiers: "k:Shift+D"; a key with modifiers matches only with exactly
## those held, a plain key only with none), "p:<joypad
## button>", "a:<axis><+|->" (a stick or trigger pushed that way) or "m:<mouse button>" (in a
## key slot, with its modifiers like a key's: "m:Ctrl+Right").
## The menu actions also feed Godot's own ui_* actions (Enter / pad A press a
## focused button, the arrows / D-pad move the focus), so every menu built of
## focusable controls gets keyboard and gamepad navigation.
##
## Menu navigation (this node, last in line for unhandled input): when a game
## menu that registered with register_menu() is open, the menu direction
## actions (WASD as well as the arrows / D-pad / left stick) move the focus
## between its controls - the first press focuses its first control - and
## menu_tab_prev / menu_tab_next switch its tabs (the menu's cycle_tab(dir)).
##
## The 3D game reads the held ones (forward, boost, up...) with Input.is_action_pressed
## and the presses with pressed() - CosmosShip, CosmosWalker, Cosmos.

signal changed

const FILE := "user://keybinds.cfg"
const DEADZONE := 0.3

## [id, group, label, [key 1, key 2, pad]]
const ACTIONS := [
	["menu_up", "Menus", "Up", ["k:W", "k:Up", "p:11"]],
	["menu_down", "Menus", "Down", ["k:S", "k:Down", "p:12"]],
	["menu_left", "Menus", "Left / less", ["k:A", "k:Left", "p:13"]],
	["menu_right", "Menus", "Right / more", ["k:D", "k:Right", "p:14"]],
	["menu_accept", "Menus", "Select / buy", ["k:Enter", "k:Space", "p:0"]],
	["menu_secondary", "Menus", "Secondary action / sell", ["k:Backspace", "", "p:2"]],
	["menu_back", "Menus", "Back / close", ["k:Escape", "", "p:1"]],
	["menu_tab_prev", "Menus", "Previous tab", ["k:Q", "", "p:9"]],
	["menu_tab_next", "Menus", "Next tab", ["k:E", "", "p:10"]],
	["undock", "Menus", "Undock (station menu)", ["k:Shift+D", "", "p:3"]],
	["trade_layer", "Menus", "Trade routes on the maps", ["k:T", "", "p:8"]],
	["sector_map", "Game", "Maps (Automaton)", ["k:M", "", ""]],
	["galaxy_map", "Game", "Galaxy map (Automaton)", ["k:G", "", ""]],
	["pause", "Ship and on foot", "Menu", ["k:Escape", "", "p:6"]],
	["computer", "Ship and on foot", "Automaton", ["k:Tab", "", "p:4"]],
	["inventory", "Ship and on foot", "Inventory", ["k:I", "", ""]],
	["forward", "Ship and on foot", "Throttle up / walk forward", ["k:W", "k:Up", "a:5+"]],
	["back", "Ship and on foot", "Throttle down / walk back", ["k:S", "k:Down", "a:4+"]],
	["left", "Ship and on foot", "Roll left / walk left", ["k:A", "k:Left", ""]],
	["right", "Ship and on foot", "Roll right / walk right", ["k:D", "k:Right", ""]],
	["boost", "Ship and on foot", "Boost / run", ["k:Shift", "", "p:0"]],
	["up", "Ship and on foot", "Thrusters up / jump", ["k:R", "k:Space", ""]],
	["down", "Ship and on foot", "Thrusters down", ["k:F", "k:Ctrl", ""]],
	["strafe_left", "Ship and on foot", "Thrusters left / strafe left", ["k:Q", "", ""]],
	["use", "Ship and on foot", "Thrusters right / strafe right", ["k:E", "", ""]],
	["stop", "Ship and on foot", "Stop (throttle to zero)", ["k:X", "", "p:1"]],
	["centre", "Ship and on foot", "Centre the stick", ["k:C", "", ""]],
	["hyperion", "Ship and on foot", "Hyperion drive", ["k:J", "", "p:3"]],
	["target", "Ship and on foot", "Target (nearest the middle)", ["k:T", "", "p:9"]],
	["land", "Ship and on foot", "Land / take off / ask a station for a pad / undock", ["k:L", "", "p:10"]],
	["dock", "Ship and on foot", "Ask a station for a landing pad", ["", "", ""]],
	["stand_up", "Ship and on foot", "Up from the pilot's seat", ["k:U", "", ""]],
	["attack", "Ship and on foot", "Fire (held)", ["", "", ""]],
	["ship_call", "Ship and on foot", "Dismiss / recall your ship (on foot)", ["k:B", "", ""]],
	["tool", "Ship and on foot", "Rifle / terrain digger (on foot)", ["k:V", "", ""]],
	["scan", "Ship and on foot", "Scanner: deposits and places round you (on foot)", ["k:Z", "", ""]],
	["drop", "Ship and on foot", "Set down / pick up a package (on foot)", ["k:H", "", ""]],
	["build_menu", "Ship and on foot", "Builder: its pieces, tier, style and paint (on foot)", ["k:N", "", ""]],
	["build_rotate", "Ship and on foot", "Builder: turn the piece", ["k:K", "m:Middle", ""]],
	["build_mode", "Ship and on foot", "Builder: build / demolish / upgrade / paint", ["k:O", "", ""]],
	["build_snap", "Ship and on foot", "Builder: snapping on / off", ["k:P", "", ""]],
	["lock", "Ship and on foot", "Lock / unlock a door or gate you built (on foot)", ["k:Y", "", ""]],
	["tutor", "Game", "Show / hide the tutorial's panel", ["k:F2", "", ""]],
	["free_mouse", "Mouse", "Free the mouse (the cursor) / capture it again (a click - a drag turns the camera)", ["m:Right", "", ""]],
	["pointer", "Mouse", "Free mouse: select (click), steer and look (hold and drag)", ["m:Left", "", ""]],
	["slot_1", "Toolbar", "Slot 1", ["k:1", "", ""]],
	["slot_2", "Toolbar", "Slot 2", ["k:2", "", ""]],
	["slot_3", "Toolbar", "Slot 3", ["k:3", "", ""]],
	["slot_4", "Toolbar", "Slot 4", ["k:4", "", ""]],
	["slot_5", "Toolbar", "Slot 5", ["k:5", "", ""]],
	["slot_6", "Toolbar", "Slot 6", ["k:6", "", ""]],
	["slot_7", "Toolbar", "Slot 7", ["k:7", "", ""]],
	["slot_8", "Toolbar", "Slot 8", ["k:8", "", ""]],
	["slot_9", "Toolbar", "Slot 9", ["k:9", "", ""]],
	["quicksave", "Game", "Quicksave", ["k:F5", "", ""]],
	["quickload", "Game", "Quickload", ["k:F9", "", ""]],
	["talos", "Game", "Open Talos", ["k:F8", "", ""]],
	["live_edit", "Game", "Live Editor: edit anything while the game runs", ["k:F10", "", ""]],
]
## The menu actions that also drive Godot's ui_* (focus, buttons).
const UI_MIRROR := {"menu_accept": "ui_accept", "menu_back": "ui_cancel"}
## Left stick on the menu directions (always, besides the three slots).
const STICK := {"menu_up": "a:1-", "menu_down": "a:1+", "menu_left": "a:0-", "menu_right": "a:0+"}

var binds := {}          # id -> [3 slot strings]
var _menus: Array = []   # registered game menus (Controls), see register_menu


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS   # (menus run with the game paused)
	load_binds()


# --- The bindings -------------------------------------------------------------------

static func defaults(id: String) -> Array:
	for a in ACTIONS:
		if a[0] == id:
			return a[3].duplicate()
	return ["", "", ""]


static func label(id: String) -> String:
	for a in ACTIONS:
		if a[0] == id:
			return a[2]
	return id


func load_binds() -> void:
	binds = {}
	for a in ACTIONS:
		binds[a[0]] = a[3].duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(FILE) == OK:
		for id in binds:
			var v = cfg.get_value("binds", id) if cfg.has_section_key("binds", id) else null
			if v is Array and v.size() == 3:
				binds[id] = v.map(func(s): return str(s))
	_apply()


func save_binds() -> void:
	var cfg := ConfigFile.new()
	for id in binds:
		if binds[id] != defaults(id):
			cfg.set_value("binds", id, binds[id])
	cfg.save(FILE)


## Bind `slot` (0, 1: keys; 2: pad) of `id` to `spec` ("" clears it).
func set_bind(id: String, slot: int, spec: String) -> void:
	binds[id][slot] = spec
	_apply()
	save_binds()


func reset(id := "") -> void:
	for a in ACTIONS:
		if id == "" or a[0] == id:
			binds[a[0]] = a[3].duplicate()
	_apply()
	save_binds()


## Other actions of the same group using `spec` (a clash to point out).
## The free mouse's own (only while it's free: never at once with the others).
const FREE_MOUSE_ONLY := ["pointer"]


func clashes(id: String, spec: String) -> Array:
	if spec == "":
		return []
	if id in FREE_MOUSE_ONLY:
		return []
	var group := ""
	for a in ACTIONS:
		if a[0] == id:
			group = a[1]
	var out := []
	for a in ACTIONS:
		if a[0] != id and not a[0] in FREE_MOUSE_ONLY and spec in binds[a[0]] and (a[1] == group or (group != "Menus" and a[1] != "Menus")):
			out.append(a[0])
	return out


## Puts every binding into the InputMap (and the ui_* mirrors).
func _apply() -> void:
	for a in ACTIONS:
		var id: String = a[0]
		if InputMap.has_action(id):
			InputMap.action_erase_events(id)
		else:
			InputMap.add_action(id, 0.5)
		var specs: Array = binds[id].duplicate()
		if STICK.has(id):
			specs.append(STICK[id])
		for s in specs:
			var ev := to_event(s)
			if ev:
				InputMap.action_add_event(id, ev)
	for id in UI_MIRROR:
		var ui: String = UI_MIRROR[id]
		# ui_accept keeps its own Enter / Space; add ours (pad A, a rebound key).
		for s in binds[id]:
			var ev := to_event(s)
			if ev and not InputMap.action_has_event(ui, ev):
				InputMap.action_add_event(ui, ev)
	changed.emit()


static func to_event(spec: String) -> InputEvent:
	if spec.length() < 3:
		return null
	var v := spec.substr(2)
	match spec[0]:
		"k":
			var code := OS.find_keycode_from_string(v)
			if code & KEY_CODE_MASK == KEY_NONE:
				return null
			var k := InputEventKey.new()
			k.keycode = code & KEY_CODE_MASK
			k.shift_pressed = code & KEY_MASK_SHIFT != 0
			k.ctrl_pressed = code & KEY_MASK_CTRL != 0
			k.alt_pressed = code & KEY_MASK_ALT != 0
			k.meta_pressed = code & KEY_MASK_META != 0
			return k
		"p":
			var b := InputEventJoypadButton.new()
			b.button_index = int(v) as JoyButton
			return b
		"a":
			var m := InputEventJoypadMotion.new()
			m.axis = int(v.left(-1)) as JoyAxis
			m.axis_value = -1.0 if v.ends_with("-") else 1.0
			return m
		"m":
			var parts := v.split("+")
			var btn: int = MOUSE_BUTTONS.find_key(parts[-1]) if MOUSE_BUTTONS.values().has(parts[-1]) else 0
			if btn == 0:
				return null
			var mb := InputEventMouseButton.new()
			mb.button_index = btn as MouseButton
			mb.ctrl_pressed = "Ctrl" in parts
			mb.shift_pressed = "Shift" in parts
			mb.alt_pressed = "Alt" in parts
			mb.meta_pressed = "Meta" in parts
			return mb
	return null


## The mouse buttons a binding can name (the wheel isn't one: it zooms).
const MOUSE_BUTTONS := {MOUSE_BUTTON_LEFT: "Left", MOUSE_BUTTON_RIGHT: "Right", MOUSE_BUTTON_MIDDLE: "Middle",
	MOUSE_BUTTON_XBUTTON1: "Back", MOUSE_BUTTON_XBUTTON2: "Forward"}


## The slot string for an input the player pressed ("" if it can't be bound).
static func spec_of(ev: InputEvent) -> String:
	if ev is InputEventKey and ev.pressed:
		var code: int = ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode
		if code == KEY_NONE or code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			return ""   # (a modifier alone: wait for the key it goes with)
		return "k:" + OS.get_keycode_string(code | (ev.get_modifiers_mask() as int))
	if ev is InputEventMouseButton and ev.pressed and MOUSE_BUTTONS.has(ev.button_index):
		var mods := ""
		for m in [["Ctrl", ev.ctrl_pressed], ["Shift", ev.shift_pressed], ["Alt", ev.alt_pressed], ["Meta", ev.meta_pressed]]:
			if m[1]:
				mods += m[0] + "+"
		return "m:" + mods + MOUSE_BUTTONS[ev.button_index]
	if ev is InputEventJoypadButton and ev.pressed:
		return "p:%d" % ev.button_index
	if ev is InputEventJoypadMotion and absf(ev.axis_value) > 0.6:
		return "a:%d%s" % [ev.axis, "+" if ev.axis_value > 0.0 else "-"]
	return ""


const PAD_NAMES := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 5: "Guide", 6: "Start", 7: "L3", 8: "R3",
	9: "LB", 10: "RB", 11: "D-pad up", 12: "D-pad down", 13: "D-pad left", 14: "D-pad right"}
const AXIS_NAMES := {"0-": "Left stick left", "0+": "Left stick right", "1-": "Left stick up", "1+": "Left stick down",
	"2-": "Right stick left", "2+": "Right stick right", "3-": "Right stick up", "3+": "Right stick down", "4+": "LT", "5+": "RT"}


## A slot as the player reads it ("W", "Enter", "RB", "RT"...).
static func spec_text(spec: String) -> String:
	if spec.length() < 3:
		return ""
	var v := spec.substr(2)
	match spec[0]:
		"k":
			return v
		"m":   # ("Ctrl+Right click")
			return v + " click"
		"p":
			return PAD_NAMES.get(int(v), "Button %s" % v)
		"a":
			return AXIS_NAMES.get(v, "Axis %s" % v)
	return spec


## "W / Up" - an action's keys (and pad, with `pad`), for hints and tooltips.
func keys_text(id: String, pad := false) -> String:
	var parts := []
	for i in 3:
		if i == 2 and not pad:
			break
		var t := spec_text(binds.get(id, ["", "", ""])[i])
		if t != "":
			parts.append(t)
	return " / ".join(parts)


## True on the press of `id` (no key repeat). A stick or trigger counts once
## each time it's pushed past half way (it must come back first: its motion
## events stream in all the while it's held).
func pressed(ev: InputEvent, id: String) -> bool:
	if not InputMap.has_action(id):
		return false
	if ev is InputEventJoypadMotion:
		return _axis_press(ev, id)
	return ev.is_action_pressed(id, false, true)


## The same, allowing key repeat (menu movement: hold to keep moving).
func pressed_repeat(ev: InputEvent, id: String) -> bool:
	if not InputMap.has_action(id):
		return false
	if ev is InputEventJoypadMotion:
		return _axis_press(ev, id)
	return ev.is_action_pressed(id, true, true)


## Like pressed_repeat, but held modifiers don't matter (Shift + a direction:
## a bigger step).
func pressed_loose(ev: InputEvent, id: String) -> bool:
	if not InputMap.has_action(id):
		return false
	if ev is InputEventJoypadMotion:
		return _axis_press(ev, id)
	return ev.is_action_pressed(id, true, false)


var _latch := {}   # "<action>|<axis>" -> held past half way

func _axis_press(ev: InputEventJoypadMotion, id: String) -> bool:
	var key := "%s|%d" % [id, ev.axis]
	for e in InputMap.action_get_events(id):
		if e is InputEventJoypadMotion and e.axis == ev.axis:
			if signf(e.axis_value) == signf(ev.axis_value) and absf(ev.axis_value) >= 0.5:
				if _latch.get(key, false):
					return false
				_latch[key] = true
				return true
	return false


## A stick or trigger back near the middle: it can count again (_axis_press).
func _input(ev: InputEvent) -> void:
	if ev is InputEventJoypadMotion and absf(ev.axis_value) < 0.35 and not _latch.is_empty():
		var tail := "|%d" % ev.axis
		for k in _latch:
			if k.ends_with(tail):
				_latch[k] = false


## The 1-9 toolbar slot this event presses (-1: none).
func slot_pressed(ev: InputEvent) -> int:
	for i in 9:
		if pressed(ev, "slot_%d" % (i + 1)):
			return i
	return -1


## The left stick, past the dead zone (zero otherwise), on any pad.
static func stick_vector() -> Vector2:
	for dev in Input.get_connected_joypads():
		var v := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		if v.length() > DEADZONE:
			return v.normalized() * inverse_lerp(DEADZONE, 1.0, minf(v.length(), 1.0))
	return Vector2.ZERO


static func pad_connected() -> bool:
	return not Input.get_connected_joypads().is_empty()


# --- Menu navigation ---------------------------------------------------------------

## A game menu (a Control) taking part in menu navigation while visible. It
## may have cycle_tab(dir: int) for the tab actions.
func register_menu(menu: Control) -> void:
	if not menu in _menus:
		_menus.append(menu)


## The open game menu on top (the last registered one visible), or null.
func active_menu() -> Control:
	for i in range(_menus.size() - 1, -1, -1):
		var m = _menus[i]
		if not is_instance_valid(m):
			_menus.remove_at(i)
		elif m.is_visible_in_tree():
			return m
	return null


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouse or (ev is InputEventKey and not ev.pressed):
		return
	var menu := active_menu()
	if menu == null or UI.esc_menu_open():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if pressed(ev, "menu_tab_prev") or pressed(ev, "menu_tab_next"):
		if menu.has_method("cycle_tab"):
			menu.cycle_tab(-1 if pressed(ev, "menu_tab_prev") else 1)
			get_viewport().set_input_as_handled()
		return
	var side := -1
	for d in [["menu_up", SIDE_TOP], ["menu_down", SIDE_BOTTOM], ["menu_left", SIDE_LEFT], ["menu_right", SIDE_RIGHT]]:
		if pressed_repeat(ev, d[0]):
			side = d[1]
	if side < 0:
		return
	get_viewport().set_input_as_handled()
	if focus == null or not menu.is_ancestor_of(focus) or not focus.is_visible_in_tree():
		var first := first_focusable(menu)
		if first:
			first.grab_focus()
		return
	var next := focus.find_valid_focus_neighbor(side)
	if next and next.is_visible_in_tree() and menu.is_ancestor_of(next):
		next.grab_focus()


## The first visible control in `root` that takes focus (depth first).
static func first_focusable(root: Node) -> Control:
	for c in root.get_children():
		if c is Control and not c.is_visible_in_tree():
			continue
		if c is Control and c.focus_mode != Control.FOCUS_NONE and not (c is Button and c.disabled):
			return c
		var f := first_focusable(c)
		if f:
			return f
	return null
