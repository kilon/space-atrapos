extends TestCase
## Loot (CosmosLoot): every enemy, person and animal that dies drops loot by
## its body - what's in it by what it was - and walking up to it you take it
## into your inventory (what fits), the event log noting it; gone after a while.


class FakeCosmos:
	extends Node
	var walker: Node3D = null
	var hud = null
	var creatures: Array = []
	var npcs: Array = []


class FakeWalker:
	extends Node3D
	var deck = null


func _rng(seed := 7) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


func _data() -> Node:
	if CosmosGame.data == null or not is_instance_valid(CosmosGame.data):
		CosmosGame.data = load("res://scripts/sim/player_data.gd").new()
	return CosmosGame.data


func test_new_items_in_the_catalogue() -> void:
	for id in ["game_meat", "raw_hide", "beast_bone"]:
		check(Items.exists(id), "%s is an item" % id)
		check(Items.is_cargo(id), "%s is cargo (sold at markets)" % id)
		check(int(Items.info(id).get("value", 0)) > 0, "%s is worth something" % id)
		check(Items.display_name(id) != id, "%s has a name" % id)


func test_animals_leave_meat_hides_bones() -> void:
	var rng := _rng()
	var c := CosmosCreature.new()
	c.kind = CosmosFauna.species("boar", rng)
	var got := CosmosLoot.contents_for(c, rng)
	check(int(got.get("game_meat", 0)) >= 1, "a boar: meat (%s)" % str(got))
	check(int(got.get("raw_hide", 0)) >= 1, "a boar: its hide")
	check(int(got.get("beast_bone", 0)) >= 1, "a boar: bones")
	check(not got.has("cyber_matter"), "a boar's no alien")
	check_eq(CosmosLoot.title_of(c), "wild boar", "named for the prompt")
	c.free()
	# An alien beast (a world's own design, not one of the 2D game's): cybernetic matter; a monster: titan bones.
	var alien := CosmosCreature.new()
	alien.kind = {"name": "Kamirodon", "temper": "predator", "legs": 6, "size": 1.6, "scale": 3.0, "monster": true}
	var ag := CosmosLoot.contents_for(alien, rng)
	check(int(ag.get("cyber_matter", 0)) >= 1, "an alien: cybernetic matter (%s)" % str(ag))
	check(int(ag.get("titan_bones", 0)) == 1, "a monster: titan bones")
	alien.free()


func test_people_leave_their_kind_of_loot() -> void:
	var rng := _rng(3)
	var pirate := CosmosNpc.new()   # (a camp's pirate: its role "pirate")
	var pg := CosmosLoot.contents_for(pirate, rng)
	check(int(pg.get("credits", 0)) >= 20, "a pirate: drachmas (%s)" % str(pg))
	check(int(pg.get("rifle_charges", 0)) >= 1, "a pirate: rifle charges")
	check_eq(CosmosLoot.title_of(pirate), "pirate", "named")
	pirate.free()
	var sk := CosmosNpc.new()
	sk._as_foe(5, "skeleton", false)
	var sg := CosmosLoot.contents_for(sk, rng)
	check(int(sg.get("credits", 0)) >= 30, "a skeleton: old coins (%s)" % str(sg))
	sk.free()
	var lord := CosmosNpc.new()
	lord._as_foe(5, "demon", true)
	var lg := CosmosLoot.contents_for(lord, rng)
	check(int(lg.get("credits", 0)) >= 600 and int(lg.get("void_crystals", 0)) >= 1, "the demon lord: a hoard (%s)" % str(lg))
	check_eq(CosmosLoot.title_of(lord), "demon lord", "named")
	lord.free()
	var trader := CosmosTraveller.new()
	trader.role = "trader"
	trader.goods = {"wine": 4, "figs": 2}
	var tg := CosmosLoot.contents_for(trader, rng)
	check(int(tg.get("wine", 0)) == 4 and int(tg.get("figs", 0)) == 2, "a trader: its wares (%s)" % str(tg))
	trader.free()
	# Never empty, and only what the catalogue knows.
	for role in ["guard", "courier", "pilgrim", "raider", "vendor", "kilon"]:
		var n := CosmosNpc.new()
		n.role = role
		var g := CosmosLoot.contents_for(n, rng)
		check(not g.is_empty(), "%s: something" % role)
		for id in g:
			check(id == "credits" or Items.exists(id), "%s: %s is an item" % [role, id])
		n.free()


func test_a_body_drops_a_pouch_once_and_you_take_it() -> void:
	var fc := FakeCosmos.new()
	tree.root.add_child(fc)
	var holder := Node3D.new()
	fc.add_child(holder)
	var w := FakeWalker.new()
	fc.add_child(w)
	fc.walker = w
	var loot := CosmosLoot.of(fc)
	check(loot != null and loot == CosmosLoot.of(fc), "one loot node a Cosmos")
	var data := _data()
	var cr0: int = data.credits
	var e := loot.drop(holder, Vector3(10, 0, 0), Vector3.UP, "pirate", {"credits": 40, "rifle_charges": 2})
	check(loot.drops.size() == 1 and is_instance_valid(e["node"]), "a pouch on the ground")
	w.global_position = Vector3(30, 0, 0)
	check(CosmosLoot.prompt(fc).is_empty(), "no prompt from afar")
	w.global_position = Vector3(11, 0, 0)
	var p := CosmosLoot.prompt(fc)
	check(p.size() == 2 and str(p[0]) == "Loot the pirate" and str(p[1]) == "loot", "the prompt within reach (%s)" % str(p))
	var n0: int = data.count("rifle_charges")
	loot.take()
	check_eq(data.credits - cr0, 40, "the drachmas yours")
	check_eq(data.count("rifle_charges") - n0, 2, "the rifle charges yours")
	await tree.process_frame
	check(loot.drops.is_empty(), "the pouch gone once emptied")
	# Bodies found by themselves (a dead creature in the list): dropped once only.
	var c := CosmosCreature.new()
	c.kind = CosmosFauna.species("goat", _rng())
	c.dead = true
	fc.creatures.append(c)
	holder.add_child(c)
	loot._scan = 0.0
	loot._process(0.01)
	loot._scan = 0.0
	loot._process(0.01)
	check_eq(loot.drops.size(), 0, "a body with no world under it: none (no planet)")
	# They last LAST seconds.
	loot.drop(holder, Vector3.ZERO, Vector3.UP, "goat", {"game_meat": 1}, 1.0)
	loot._process(0.5)
	check_eq(loot.drops.size(), 1, "still there")
	loot._process(0.6)
	check_eq(loot.drops.size(), 0, "gone when its time's up")
	fc.queue_free()
	await tree.process_frame


func test_the_pouch_mesh_faces_out() -> void:
	var m := CosmosLoot.mesh()
	check(m == CosmosLoot.mesh(), "one mesh, shared")
	check(m.get_surface_count() == 1, "one surface")
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	check(v.size() < 400, "small (%d vertices)" % v.size())
	var bad := 0
	for k in range(0, idx.size(), 3):
		var p0 := v[idx[k]]
		var nrm := (v[idx[k + 1]] - p0).cross(v[idx[k + 2]] - p0)
		var cen := (p0 + v[idx[k + 1]] + v[idx[k + 2]]) / 3.0
		if nrm.length() > 1e-7 and idx[k] < v.size() - 8 and nrm.dot(cen - Vector3(0, 0.16, 0)) > 0.0:
			bad += 1
	check_eq(bad, 0, "every triangle wound to face out (clockwise front faces)")
