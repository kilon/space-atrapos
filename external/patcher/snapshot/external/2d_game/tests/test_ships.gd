extends TestCase
## Ship and station catalogues, their vector art and the shipyards.

const KEYS := ["name", "length", "hull", "shields", "speed", "fire_interval", "damage", "bullet_speed", "shots", "aggro", "distance", "color"]
const EMPIRES := ["athens", "sparta", "minoa", "mycenae", "pirates"]


func test_catalogue_complete() -> void:
	var ids := EnemyTypes.all_ids()
	check(ids.size() >= 60, "only %d ship types" % ids.size())
	for id in ids:
		var t := EnemyTypes.get_type(id)
		for k in KEYS:
			check(t.has(k), "%s lacks %s" % [id, k])
		check(t.get("hull", 0.0) > 0.0 and t.get("speed", 0.0) > 0.0, id + ": hull / speed must be positive")
	check(not EnemyTypes.ids().is_empty(), "no hostile classes")
	check(not EnemyTypes.neutral_ids().is_empty(), "no neutral classes")
	check(EnemyTypes.get_type("no_such_ship") == EnemyTypes.get_type(EnemyTypes.FALLBACK), "unknown ids fall back")


func test_empire_fleets() -> void:
	for e in ["athens", "sparta", "minoa", "pirates"]:
		var own := 0
		for i in 20:
			var id := ShipDesigns.warship(e)
			check(EnemyTypes.has_type(id), "%s warship %s unknown" % [e, id])
			if EnemyTypes.get_type(id).get("empire_style", "") == e:
				own += 1
		check(own >= 10, "%s flies its own warships only %d/20 times" % [e, own])
	for e in EMPIRES:
		check(ShipDesigns.warship(e) != "", e + " has no warships")


func test_civil_roles() -> void:
	for e in ["athens", "sparta", "minoa", "mycenae"]:
		for role in ["trader", "miner", "explorer"]:
			var id := ShipDesigns.pick(e, [role])
			check(id != "" and EnemyTypes.get_type(id).get("role", "") == role, "%s has no %s ship (got '%s')" % [e, role, id])


func test_bosses_drawn_with_traced_hulls() -> void:
	for b in EnemyTypes.BOSSES:
		var art: String = EnemyTypes.BOSSES[b]["art"]
		check(TracedShips.def(art).size() > 0, "%s uses missing art %s" % [b, art])


func test_ship_sprites() -> void:
	for id in EnemyTypes.all_ids() + ["player"]:
		var tex: Texture2D = ProcArt.get_tex("ship_player") if id == "player" else ProcArt.ship_texture(id)
		if check(tex != null, "no sprite for ship " + id):
			check(tex.get_height() >= 120 and tex.get_width() >= 60, "%s sprite is %s" % [id, tex.get_size()])
			check(tex.get_height() >= tex.get_width() * 0.6, id + ": ships point nose-up")


func test_stations() -> void:
	for d in StationArt.ids():
		check(ProcArt.has_sprite("station_" + d), "no sprite for station " + d)
	for e in EMPIRES:
		check(StationArt.DESIGNS.has(StationArt.design_for(e, "x")), e + " picks an unknown station design")


func test_shipyards() -> void:
	for e in ["athens", "sparta", "minoa", "mycenae"]:
		var sale := Shipyard.for_sale(e)
		check(sale.size() >= 12, "%s shipyard sells only %d ships" % [e, sale.size()])
		for id in sale:
			var st := Shipyard.stats(id)
			check(st["price"] > 0 and st["cargo"] > 0, "%s: bad stats %s" % [id, str(st)])
	check(Shipyard.for_sale(Galaxy.HOME_EMPIRE).has("player"), "home shipyards sell the player's class")



## Ships you buy are worth buying: each class's ships beat the Atrapos you
## start with where the class is strong (none has fewer slots), a dearer
## ship of a class is never worse, and prices grow with what a ship gives.
func test_ships_are_upgrades() -> void:
	var start := Shipyard.stats("player")
	var by_class := {}
	for id in ShipDesigns.ids():
		var st := Shipyard.stats(id)
		var cls := str(EnemyTypes.get_type(id).get("class", "fighter"))
		by_class.get_or_add(cls, []).append(st)
		check(st["hull"] + st["shields"] > start["hull"] + start["shields"], "%s: more hull and shields than the Atrapos (%d + %d)" % [id, st["hull"], st["shields"]])
		check(st["hardpoints"] + st["internal"] + st["utility"] >= 7, "%s: no fewer slots than the Atrapos" % id)
		check(st["price"] >= 15000, "%s: priced as an upgrade (%d cr)" % [id, st["price"]])
	for cls in by_class:
		var l: Array = by_class[cls]
		l.sort_custom(func(a, b): return a["price"] < b["price"])
		check(l[-1]["hull"] + l[-1]["shields"] >= 1.35 * (l[0]["hull"] + l[0]["shields"]), "%s: the class's best is well above its cheapest" % cls)
	check(by_class["frigate"][0]["price"] > 2 * by_class["fighter"][0]["price"], "a frigate costs far more than a fighter")
	var top := 0
	for cls in by_class:
		for st in by_class[cls]:
			top = maxi(top, st["price"])
	check(top >= 1000000, "the best ships cost a million drachmas or more (%d)" % top)
	check(by_class["frigate"][0]["hull"] > 4 * start["hull"], "a frigate is far tougher than the Atrapos")

## The trade-in is 80% of what you paid; the ship you start with counts as
## START_SHIP_VALUE, so no shipyard pays you to swap it at the start.
func test_trade_in_is_what_you_paid() -> void:
	var d = load("res://scripts/player_data.gd").new()
	check_eq(Shipyard.trade_in(d), roundi(d.START_SHIP_VALUE * 0.8), "the starting ship trades in at 80% of its value")
	for e in Galaxy.MAJOR:
		for id in Shipyard.for_sale(e):
			if id != d.ship_class:
				check(Shipyard.stats(id)["price"] - Shipyard.trade_in(d) > 0, "%s: swapping the starting ship isn't free money" % id)
	# A bought ship trades in at 80% of its price; saved and loaded.
	d.ship_class = "player"
	d.ship_value = 8000
	check_eq(Shipyard.trade_in(d), 6400, "a bought Atrapos-class: 80% of 8000")
	var d2 = load("res://scripts/player_data.gd").new()
	d2.load_save_data(JSON.parse_string(JSON.stringify(d.get_save_data())))
	check_eq(d2.ship_value, 8000, "the value is saved")
	# Older saves (no value): the starting ship at its start value.
	var old: Dictionary = d.get_save_data()
	old.erase("ship_value")
	d2.load_save_data(old)
	check_eq(d2.ship_value, d.START_SHIP_VALUE, "an old save's starting ship")
	d.free()
	d2.free()


func test_sprites_are_clean_cutouts() -> void:
	# Every sprite: transparent corners (no background left), no long dark bars.
	var n := 0
	for j in ProcArt.bake_jobs():
		if not str(j[1]).begins_with("res://data/sprites/"):
			continue
		var img: Image = ProcArt.get_image(j[0])
		n += 1
		var w := img.get_width()
		var h := img.get_height()
		var corners := 0
		for p in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
			if img.get_pixelv(p).a < 0.5:
				corners += 1
		# (tile pieces like columns fill their whole rectangle)
		check(corners >= (0 if str(j[0]).begins_with("tile_") or str(j[0]).begins_with("sky_gg_band") else 3), "%s: background left in the corners" % j[0])   # (tiles and the cloud bands fill their rectangle)
		if str(j[0]).begins_with("npc_") and not str(j[0]).contains("portrait"):
			var worst := 0
			for y in h:
				var run := 0
				for x in w:
					var c := img.get_pixel(x, y)
					run = run + 1 if c.a > 0.5 and c.get_luminance() < 0.05 else 0
					worst = maxi(worst, run)
			check(worst < w * 0.3, "%s: a dark bar %d px wide" % [j[0], worst])
	check(n > 150, "only %d sprites" % n)


## The outfitter's before / after: fitting a module shows what it changes,
## the same as fitting it does - and leaves the player's ship as it was.
func test_outfit_compare() -> void:
	var d = load("res://scripts/player_data.gd").new()
	var base := {"regen": 10.0}
	var mods_before: Array = d.modules.duplicate(true)
	var rows := OutfitCompare.ship_rows(d, base, "shield_generator", 2)
	var sh: Array = rows.filter(func(r): return r[0] == "Shields")
	check(sh.size() == 1, "a Shield Generator changes the shields (%s)" % str(rows))
	if sh.size() == 1:
		var expect: float = Shipyard.MODULES["shield_generator"]["effects"]["max_shields"] * Shipyard.RATING_MULT[2]
		check(is_equal_approx(sh[0][2] - sh[0][1], expect), "by what fitting it gives (+%.1f)" % expect)
	check(d.modules == mods_before, "the ship is left as it was")
	# A weapon: one more fitted; its own stats.
	rows = OutfitCompare.ship_rows(d, base, "wpn:plasma_cannon:0")
	check(rows.any(func(r): return r[0] == "Weapons fitted" and r[2] == r[1] + 1.0), "a weapon: one more fitted")
	check(rows.any(func(r): return r[0] == "Firepower (damage /s)" and r[2] > r[1]), "and more firepower (they all fire)")
	check(not d.has_equipment("plasma_cannon"), "and not actually fitted")
	check(OutfitCompare.weapon_facts(d, "wpn:plasma_cannon:0").size() == 4, "a weapon's own stats")
	# Taking a fitted module out: the rows go the other way.
	d.modules.append({"id": "hull_reinforcement", "rating": 0})
	rows = OutfitCompare.ship_rows(d, base, "", 0, d.modules.size() - 1)
	check(rows.any(func(r): return r[0] == "Hull" and r[2] < r[1]), "taking one out: less hull")
	check(d.modules.size() == mods_before.size() + 1, "still fitted after the comparison")
	# Automaton gear: health from armour.
	var lo := {"weapon": Gear.DEFAULT_LOADOUT["weapon"]}
	for kind in Gear.FOOT:
		if Gear.FOOT[kind]["slot"] == "armour" and Gear.FOOT[kind].get("effects", {}).has("max_hp"):
			rows = OutfitCompare.foot_rows(lo, Gear.item_id(kind, 0))
			check(rows.any(func(r): return r[0] == "Health" and r[2] > r[1]), "armour adds health (%s)" % kind)
			break
	check(lo.size() == 1, "the loadout is left as it was")
