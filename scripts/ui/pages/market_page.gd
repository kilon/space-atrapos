extends HBoxContainer
class_name MarketPage
## The station's commodity market (Station menu > MARKET): a trading terminal.
## Left: every good in a table, grouped by category - what the station pays
## (SELL) and asks (BUY), the galactic average and how far this price is from
## it, the station's supply and demand (bars) and what you carry. Right: the
## selected good - its prices, a quantity picker, Buy / Sell and where it
## sells best within two jumps (plot a route there).
## Keys (Keybinds, rebindable): W/S or the arrows / D-pad pick a good, A/D the
## quantity, Enter / pad A buy, Backspace / pad X sell. The selection and quantity stay while the page is rebuilt (every
## trade rebuilds it).

const GREEN := Color(0.45, 1.0, 0.55)
const RED := Color(1.0, 0.45, 0.35)
## Column widths at text scale 1 (the commodity column takes the rest).
const COLS := [["SELL", 84], ["BUY", 84], ["GALACTIC AVG", 150], ["SUPPLY", 120], ["DEMAND", 110], ["CARGO", 72]]

static var selected := "food"
static var qty := 1
## The category shown (TradeRoutes.CATEGORIES index): one tab each.
static var category := 0

var menu: Node            # the station menu (data, station, refresh)
var data: Node
var sid := ""
var _rows := {}           # item -> its row button
var _k := 1.0             # text scale


func setup(m: Node) -> void:
	menu = m
	data = m.data
	sid = m.station.station_id
	_k = Settings.font_scale("menu")
	add_theme_constant_override("separation", 18)
	size_flags_horizontal = SIZE_EXPAND_FILL
	category = clampi(category, 0, TradeRoutes.CATEGORIES.size() - 1)
	var goods := _goods()
	if not selected in goods:
		selected = goods[0] if not goods.is_empty() else Galaxy.COMMODITIES[0]
	add_child(_table())
	add_child(_detail())


# --- The table -----------------------------------------------------------------

## The goods of the category shown that this station deals in.
func _goods() -> Array:
	var stock: Dictionary = Galaxy.stations[sid]["stock"]
	return TradeRoutes.CATEGORIES[category][1].filter(func(c): return stock.has(c))


func _table() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	# A tab per category, with how many of its goods this station deals in.
	var stock: Dictionary = Galaxy.stations[sid]["stock"]
	var names := TradeRoutes.CATEGORIES.map(func(cat): return "%s %d" % [cat[0], cat[1].filter(func(c): return stock.has(c)).size()])
	var tabs: Container = menu._sub_tabs(names, category, func(i):
		category = i
		menu.refresh(), 2)
	col.add_child(tabs)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	col.add_child(gap)
	col.add_child(_header())
	var rec: Dictionary = Galaxy.stations[sid]
	var goods := _goods()
	for c in goods:
		col.add_child(_row(c, rec))
	if goods.is_empty():
		col.add_child(UI.label("This station doesn't trade in %s." % TradeRoutes.CATEGORIES[category][0].to_lower(), 14, UI.TEXT_DIM))
	return col


func _header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	var name := UI.label("COMMODITY", 14, UI.TEXT_DIM)
	name.size_flags_horizontal = SIZE_EXPAND_FILL
	name.add_theme_constant_override("margin_left", 10)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 46)
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	pad.add_child(name)
	h.add_child(pad)
	for c in COLS:
		var l := UI.label(c[0], 14, UI.TEXT_DIM)
		l.custom_minimum_size.x = c[1] * _k
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if c[0] in ["SELL", "BUY", "CARGO"] else HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(l)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_bottom", 4)
	m.add_theme_constant_override("margin_right", 10)
	m.add_child(h)
	return m


## One good: a flat button (click / Enter selects it) holding the columns.
func _row(c: String, rec: Dictionary) -> Button:
	var t: Dictionary = TradeRoutes.table()[sid]
	var buy: int = t[c][0]
	var sell: int = t[c][1]
	var avg := TradeRoutes.average(c)
	var sup := TradeRoutes.supply_bars(sid, c)
	var dem := TradeRoutes.demand_bars(sid, c)
	var have: int = data.count(c)
	var sel := c == selected
	var ink: Color = NeonTheme.INK if sel else Color.WHITE
	var dim: Color = Color(NeonTheme.INK, 0.75) if sel else UI.TEXT_DIM

	var b := Button.new()
	b.focus_mode = FOCUS_NONE   # (the keys move the selection: handle_key)
	b.custom_minimum_size.y = 24 * minf(_k, 1.25)   # (no taller past 125%: the text fits) (a line of text and a little air: every good on the page)
	b.add_theme_stylebox_override("normal", _row_box(sel, false))
	b.add_theme_stylebox_override("hover", _row_box(sel, true))
	b.add_theme_stylebox_override("pressed", _row_box(true, true))
	b.pressed.connect(func(): _select(c))
	b.tooltip_text = EditorIcons.tip(Items.display_name(c), "W / S", "%s\n%s" % [Items.ITEMS[c]["desc"], _tag(c, rec)])
	_rows[c] = b

	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -10
	h.add_theme_constant_override("separation", 0)
	h.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(h)
	var icon := ItemSlot.make(c, 0, 22.0 * minf(_k, 1.25))
	icon.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(icon)
	var name := UI.label("  " + Items.display_name(c), 16, ink)
	name.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(name)
	var tag := UI.label(_short_tag(c, rec), 14, dim)
	h.add_child(tag)
	h.add_child(_cell(str(sell), COLS[0][1], ink, HORIZONTAL_ALIGNMENT_RIGHT))
	h.add_child(_cell(str(buy) if sup > 0 else "-", COLS[1][1], ink if sup > 0 else dim, HORIZONTAL_ALIGNMENT_RIGHT))
	# Galactic average, and how this station's sell price compares with it.
	var diff := roundi(100.0 * (sell - avg) / maxf(1.0, avg))
	var arrow := "▲" if diff > 0 else ("▼" if diff < 0 else " ")
	var dcol: Color = (GREEN if diff > 0 else RED) if diff != 0 else dim
	if sel:
		dcol = NeonTheme.INK
	h.add_child(_cell("%d  %s%d%%" % [avg, arrow, absi(diff)], COLS[2][1], dcol, HORIZONTAL_ALIGNMENT_CENTER))
	h.add_child(_bars(sup, COLS[3][1], int(rec["stock"].get(c, 0.0)), ink, dim))
	h.add_child(_bars(dem, COLS[4][1], -1, ink, dim))
	h.add_child(_cell(str(have) if have > 0 else "", COLS[5][1], ink, HORIZONTAL_ALIGNMENT_RIGHT))
	for n in h.get_children():
		n.mouse_filter = MOUSE_FILTER_IGNORE
	return b


func _row_box(sel: bool, hover: bool) -> StyleBox:
	if sel:
		var s := NeonTheme.lit(NeonTheme.CYAN, 1, 4)
		s.content_margin_left = 0
		return s
	var f := StyleBoxFlat.new()
	f.bg_color = NeonTheme.hi_bg(0.6, 0.35) if hover else Color(0, 0, 0, 0)
	f.border_color = Color(NeonTheme.CYAN, 0.12)
	f.border_width_bottom = 1
	return f


func _cell(text: String, w: float, col: Color, align: HorizontalAlignment) -> Label:
	var l := UI.label(text, 15, col)
	l.custom_minimum_size.x = w * _k
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Three bars (lit: `n` of them), the stock beside them (`count` >= 0).
func _bars(n: int, w: float, count: int, ink: Color, dim: Color) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w * _k, 20)
	c.size_flags_vertical = SIZE_SHRINK_CENTER
	var k := _k
	c.draw.connect(func():
		var x0 := c.size.x / 2.0 - (40.0 * k if count >= 0 else 16.0 * k)
		for i in 3:
			var hgt := (6.0 + i * 4.0) * k
			var r := Rect2(x0 + i * 10.0 * k, c.size.y / 2.0 + 8.0 * k - hgt, 7.0 * k, hgt)
			c.draw_rect(r, ink if i < n else Color(dim, 0.25))
		if count >= 0:
			var f := NeonTheme.heavy_font()
			c.draw_string(f, Vector2(x0 + 36.0 * k, c.size.y / 2.0 + 6.0 * k), str(count) if n > 0 else "-", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14 * k), ink if n > 0 else dim))
	return c


func _short_tag(c: String, rec: Dictionary) -> String:
	return "MADE HERE  " if Galaxy.makes(rec["economy"], c) else ""


func _tag(c: String, rec: Dictionary) -> String:
	if Galaxy.makes(rec["economy"], c):
		return "Made here: cheap to buy."
	if Galaxy.uses(rec["economy"], c):
		return "Used here: the station pays more the shorter it is."
	return "Neither made nor used here."


# --- The selected good -------------------------------------------------------------

func _detail() -> Control:
	var c: String = selected
	var t: Dictionary = TradeRoutes.table()[sid]
	var buy: int = t[c][0]
	var sell: int = t[c][1]
	var stock := int(t[c][2])
	var have: int = data.count(c)
	var avg := TradeRoutes.average(c)
	var cap := Shipyard.cargo_capacity(data)
	var used := Galaxy.cargo_used(data)

	var p := PanelContainer.new()
	p.custom_minimum_size.x = 440 * _k
	var box := NeonTheme.box(Color(NeonTheme.CYAN, 0.6), NeonTheme.BG_LIGHT, 1, 4)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 14
	p.add_theme_stylebox_override("panel", box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(ItemSlot.make(c, have, 56.0))
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.add_child(UI.label(Items.display_name(c).to_upper(), 24, NeonTheme.HEAD))
	names.add_child(UI.label(TradeRoutes.category_of(c), 14, UI.TEXT_DIM))
	head.add_child(names)
	v.add_child(head)
	var desc := UI.label(Items.ITEMS[c]["desc"], 14, UI.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)

	# Prices.
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 20)
	g.add_theme_constant_override("v_separation", 2)
	for pair in [["Buy price", "%d dr" % buy if stock >= 1 else "none in stock"], ["Sell price", "%d dr" % sell],
			["Galactic average", "%d dr" % avg], ["Station stock", str(stock)], ["In your hold", str(have)],
			["Cargo hold", "%d / %d slots" % [used, cap]]]:
		g.add_child(UI.label(pair[0], 15, UI.TEXT_DIM))
		g.add_child(UI.label(pair[1], 15, Color.WHITE))
	v.add_child(g)

	# Quantity and the transaction.
	v.add_child(UI.section("TRANSACTION"))
	var max_buy := mini(stock, mini(data.room_for(c), data.credits / maxi(1, buy)))
	qty = clampi(qty, 1, 999)
	var q := HBoxContainer.new()
	q.add_theme_constant_override("separation", 6)
	q.add_child(_small("−", func(): _set_qty(qty - (10 if Input.is_key_pressed(KEY_SHIFT) else 1)), "Less (A; Shift: 10 less)"))
	var ql := UI.label(str(qty), 22, Color.WHITE)
	ql.custom_minimum_size.x = 64 * _k
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.add_child(ql)
	q.add_child(_small("+", func(): _set_qty(qty + (10 if Input.is_key_pressed(KEY_SHIFT) else 1)), "More (D; Shift: 10 more)"))
	q.add_child(_small("MAX", func(): _set_qty(maxi(1, maxi(max_buy, have))), "As many as you can buy - or sell, when you can't buy any"))
	q.add_child(UI.spacer())
	q.add_child(UI.label("≈ %d dr" % (qty * buy), 16, UI.GOLD))
	v.add_child(q)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 10)
	var bb := EditorIcons.action(UI.button("", _buy, 16), "buy", "Buy %d" % mini(qty, max_buy) if max_buy > 0 else "Buy",
		EditorIcons.tip("Buy %s" % Items.display_name(c), "Enter", "Buys up to %d at about %d dr each (fewer if the stock, your drachmas or your hold run out).\nEvery unit you buy raises the price here; it recovers over a few minutes." % [qty, buy]))
	bb.disabled = max_buy < 1
	bb.size_flags_horizontal = SIZE_EXPAND_FILL
	acts.add_child(bb)
	var sb := EditorIcons.action(UI.button("", _sell, 16), "sell", "Sell %d" % mini(qty, have) if have > 0 else "Sell",
		EditorIcons.tip("Sell %s" % Items.display_name(c), "Backspace", "Sells up to %d of the %d you carry at about %d dr each.\nEvery unit you sell lowers the price here - spread a big load over several stations." % [qty, have, sell]))
	sb.disabled = have < 1
	sb.size_flags_horizontal = SIZE_EXPAND_FILL
	acts.add_child(sb)
	v.add_child(acts)

	# Where it sells best (trade routes for this good from here).
	v.add_child(UI.section("BEST PRICES WITHIN 2 JUMPS"))
	var sys: String = Galaxy.stations[sid]["system"]
	var any := false
	for s in TradeRoutes.best_sellers(c, sys, 2, sid, 4):
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var where := "%s  ·  %s" % [TradeRoutes.station_name(s["to"]), "this system" if s["jumps"] == 0 else "%s, %d jump%s" % [TradeRoutes.system_name(s["to_sys"]), s["jumps"], "" if s["jumps"] == 1 else "s"]]
		var wl := UI.label(where, 14, Color.WHITE)
		wl.size_flags_horizontal = SIZE_EXPAND_FILL
		wl.clip_text = true
		row.add_child(wl)
		var profit: int = s["sell"] - buy
		row.add_child(UI.label("%d dr" % s["sell"], 14, UI.GOLD))
		row.add_child(UI.label(("%+d" % profit) if stock >= 1 else "", 14, GREEN if profit > 0 else RED))
		if s["to_sys"] != sys:
			var plot := EditorIcons.dress(UI.button("", _plot.bind(s["to_sys"]), 12), "next",
				EditorIcons.tip("Plot route to %s" % TradeRoutes.system_name(s["to_sys"]), "", "Sets your route through the jump gates; the HUD points the way once you undock."))
			plot.focus_mode = FOCUS_NONE
			row.add_child(plot)
		v.add_child(row)
	if not any:
		v.add_child(UI.label("No other market within reach.", 14, UI.TEXT_DIM))
	var tip := UI.label("Buy where it's made, sell where it's used. The galaxy map's trade layer (G) shows the best runs.", 14, UI.TEXT_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tip)
	return p


func _small(text: String, f: Callable, tip: String) -> Button:
	var b := UI.button(text, f, 16)
	b.custom_minimum_size = Vector2(40, 34) * _k
	b.focus_mode = FOCUS_NONE
	b.tooltip_text = tip
	return b


# --- Actions ---------------------------------------------------------------------

func _select(c: String) -> void:
	if c == selected:
		return
	selected = c
	menu.refresh()


func _set_qty(n: int) -> void:
	qty = clampi(n, 1, 999)
	menu.refresh()


func _buy() -> void:
	var got := Galaxy.player_buy(sid, selected, qty, data)
	TradeRoutes.invalidate()
	if got > 0:
		GameLog.post("Bought %d %s" % [got, Items.display_name(selected)], "info")
	elif data.room_for(selected) < 1:
		GameLog.post("Cargo hold full (%d slots)" % Shipyard.cargo_capacity(data), "danger")
	menu.refresh()


func _sell() -> void:
	var n := mini(qty, data.count(selected))
	var earned := Galaxy.player_sell(sid, selected, n, data)
	TradeRoutes.invalidate()
	if earned > 0:
		GameLog.post("Sold %d %s for %d dr" % [n, Items.display_name(selected), earned], "loot")
	menu.refresh()


func _plot(sys_id: String) -> void:
	Galaxy.route = Galaxy.find_route(Galaxy.current_system, sys_id)
	GameLog.post("Route plotted to %s: %d jump%s." % [TradeRoutes.system_name(sys_id), Galaxy.route.size() - 1, "" if Galaxy.route.size() == 2 else "s"], "mission")


## Keys (the station menu passes them on while this page shows): W/S or the
## arrows move the selection, A/D the quantity, Enter buys, Backspace sells.
## Returns true when it used the event.
func handle_key(ev: InputEvent) -> bool:
	if Keybinds.pressed_repeat(ev, "menu_up"):
		_step(-1)
	elif Keybinds.pressed_repeat(ev, "menu_down"):
		_step(1)
	elif Keybinds.pressed_loose(ev, "menu_left"):
		_set_qty(qty - (10 if Input.is_key_pressed(KEY_SHIFT) else 1))
	elif Keybinds.pressed_loose(ev, "menu_right"):
		_set_qty(qty + (10 if Input.is_key_pressed(KEY_SHIFT) else 1))
	elif Keybinds.pressed(ev, "menu_accept"):
		_buy()
	elif Keybinds.pressed(ev, "menu_secondary"):
		_sell()
	else:
		return false
	return true


func _step(d: int) -> void:
	var order := _goods()
	if order.is_empty():
		return
	var i := order.find(selected)
	selected = order[wrapi(i + d, 0, order.size())]
	menu.refresh()
