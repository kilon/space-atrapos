extends TestCase
## The market's 140 goods (TradeGoods + the original fourteen): items, icons,
## who stocks them, the economy with them, the averages and the route search.


func test_goods_and_categories() -> void:
	check_eq(Galaxy.COMMODITIES.size(), 140, "140 trade goods")
	check_eq(TradeRoutes.CATEGORIES.size(), 10, "ten categories")
	var seen := {}
	for cat in TradeRoutes.CATEGORIES:
		check_eq(cat[1].size(), 14, "%s: fourteen goods" % cat[0])
		for c in cat[1]:
			check(not seen.has(c), "%s in one category only" % c)
			seen[c] = true
	check_eq(seen.size(), 140, "every good in a category")
	for c in Galaxy.COMMODITIES:
		var it: Dictionary = Items.ITEMS.get(c, {})
		check(it.get("kind", "") == "cargo" and str(it.get("name", "")) != "" and str(it.get("desc", "")).length() > 10 and int(it.get("value", 0)) > 0,
			"%s: a cargo item with a name, a description and a value" % c)
	# Every new good's icon draws (each shape), in a canvas item.
	var ci := Control.new()
	ci.size = Vector2(64, 64)
	tree.root.add_child(ci)
	var shapes := {}
	ci.draw.connect(func():
		for id in TradeGoods.GOODS:
			Items.draw_icon(ci, id, Rect2(Vector2.ZERO, Vector2(64, 64)))
			shapes[TradeGoods.GOODS[id]["shape"]] = true)
	ci.queue_redraw()
	await tree.process_frame
	await tree.process_frame
	check(shapes.size() >= 15, "the icons draw, in %d shapes" % shapes.size())
	ci.queue_free()


func test_stations_stock_their_goods() -> void:
	Galaxy.new_game(false)
	var total := 0
	for sid in Galaxy.stations:
		var st: Dictionary = Galaxy.stations[sid]
		total += st["stock"].size()
		for c in Galaxy.BASE_COMMODITIES:
			check(st["stock"].has(c), "%s: the original goods" % sid)
		for c in Galaxy._econ_goods[st["economy"]]["produce"]:
			check(st["stock"].has(c), "%s stocks %s (made there)" % [sid, c])
	check(total / float(Galaxy.stations.size()) > 35.0, "stations deal in many goods (%.0f each)" % (total / float(Galaxy.stations.size())))
	# Every new good is made somewhere and used somewhere.
	for id in TradeGoods.GOODS:
		var made := false
		var used := false
		for e in Galaxy.ECONOMIES:
			made = made or Galaxy.makes(e, id)
			used = used or Galaxy.uses(e, id)
		check(made and used, "%s: made and used" % id)
	# A save from before the new goods gets them when it loads.
	var d := Galaxy.get_save_data()
	var sid0: String = Galaxy.stations.keys()[0]
	for sid in d.get("stocks", {}):
		for id in TradeGoods.GOODS:
			d["stocks"][sid].erase(id)
	Galaxy.load_save_data(JSON.parse_string(JSON.stringify(d)))
	var st0: Dictionary = Galaxy.stations[sid0]
	check(Galaxy._econ_goods[st0["economy"]]["produce"].keys().all(func(c): return st0["stock"].has(c)), "an old save's stations stock the new goods")


func test_economy_runs_with_them() -> void:
	Galaxy.new_game(false)
	for i in 200:
		for sid in Galaxy.stations:
			Galaxy._economy_tick_station(sid)
			Galaxy.cache_prices(sid)
	var empty := 0
	var full := 0
	var n := 0
	for sid in Galaxy.stations:
		for c in Galaxy.stations[sid]["stock"]:
			var v: float = Galaxy.stations[sid]["stock"][c]
			check(v >= 0.0 and not is_nan(v), "%s %s: a stock (%s)" % [sid, c, v])
			if TradeGoods.GOODS.has(c):
				n += 1
				empty += 1 if v < 1.0 else 0
				full += 1 if v > 319.0 else 0
	check(empty < n * 0.4 and full < n * 0.4, "the new goods' stocks spread out (%d empty, %d full of %d)" % [empty, full, n])
	# The averages kept as prices change match a recount.
	for c in ["wine", "food", "orichalcum"]:
		var sum := 0.0
		var k := 0
		for sid in Galaxy.price_cache:
			if Galaxy.price_cache[sid].has(c):
				sum += Galaxy.price_cache[sid][c][1]
				k += 1
		check(k > 0 and absf(Galaxy.average_sell(c) - sum / k) < 0.01, "%s: the kept average is the real one" % c)


func test_route_search_spread() -> void:
	Galaxy.new_game(false)
	for sid in Galaxy.stations:
		Galaxy.visited[sid] = true
	Galaxy.knowledge += 1
	TradeRoutes.invalidate()
	TradeRoutes._routes_key = ""
	var now := TradeRoutes.galaxy_routes("", 2, 10)
	check(not now.is_empty(), "routes found")
	TradeRoutes.invalidate()
	TradeRoutes._routes_key = ""
	var spread: Array = []
	var frames := 0
	while spread.is_empty() and frames < 2000:
		spread = TradeRoutes.galaxy_routes_spread("", 2, 10)
		frames += 1
	check(frames > 5, "the search takes several steps (%d)" % frames)
	check_eq(spread.map(func(r): return [r["from"], r["to"], r["item"]]), now.map(func(r): return [r["from"], r["to"], r["item"]]), "the same routes as at once")
