extends TestCase
## Particle effects as data (Fx - data/effects.json): the effects load and are
## well-formed, every one spawns and is done (pooled, reused, freed with its
## parent), edits and reloads rebuild the effects playing, the game's own uses go
## through it (CosmosBoom, the bolts), Talos's Effects editor builds and edits live
## with undo, saving goes into a mod when one's being made, and the Live Editor's
## Particles tab adds an effect kept by LiveEdits.

const SCENE := "res://scenes/editor/fx_editor.tscn"
const GAME := ["explosion", "dust_land", "dust_jet", "bolt_hit", "bolt_hit_ground", "mining_sparks"]

var _mod := ""


func teardown() -> void:
	EditTarget.mod_id = ""
	if _mod != "":
		Mods.remove(_mod)
		_mod = ""
	LiveEdits.forget("test/fx")
	LiveEdits.dirty = false
	Fx.reload_all()


func _host() -> Node3D:
	var h := Node3D.new()
	tree.root.add_child(h)
	return h


func test_data_loads_and_is_well_formed() -> void:
	Fx.reload_all()
	var names := Fx.names()
	for n in GAME:
		check(names.has(n), "the game's effect %s is defined" % n)
	var keys := {}
	for p in Fx.PARAMS:
		keys[p[0]] = p
	var bad: Array = []
	for n in names:
		var ems: Array = Fx.def(n).get("emitters", [])
		if ems.is_empty():
			bad.append("%s: no emitters" % n)
		for e in ems:
			for k in e:
				if not keys.has(k):
					bad.append("%s: unknown key %s" % [n, k])
			if not str(Fx.val(e, "material")) in Fx.MATERIALS:
				bad.append("%s: material %s" % [n, Fx.val(e, "material")])
			if not str(Fx.val(e, "mesh")) in Fx.MESHES:
				bad.append("%s: mesh %s" % [n, Fx.val(e, "mesh")])
			if not str(Fx.val(e, "shape")) in Fx.SHAPES:
				bad.append("%s: shape %s" % [n, Fx.val(e, "shape")])
			for st in Fx.val(e, "colors"):
				if Fx.color_of(st[1], Color(9, 9, 9)) == Color(9, 9, 9):
					bad.append("%s: colour %s" % [n, st[1]])
	check(bad.is_empty(), "every emitter well-formed (%s)" % ", ".join(bad))
	check(not Fx.dirty, "loaded: nothing unsaved")


func test_every_effect_spawns_and_is_done() -> void:
	var h := _host()
	var made := {}
	for n in Fx.names():
		var fx := Fx.spawn(n, h, Vector3(1, 2, 3), 1.5, Fx.basis_up(Vector3.RIGHT))
		check(fx != null and fx.playing, "%s spawns and plays" % n)
		check_eq(fx.get_children().filter(func(c): return c is CPUParticles3D).size(), (Fx.def(n)["emitters"] as Array).size(), "%s: an emitter each" % n)
		check(fx.global_position.is_equal_approx(Vector3(1, 2, 3)) and is_equal_approx(fx.global_basis.y.length(), 1.5), "%s: where and how big it was asked" % n)
		made[n] = fx
	await tree.process_frame
	for n in made:
		var fx: Fx = made[n]
		fx._process(fx._life + 0.1)
		check(not fx.playing and not fx.visible, "%s: done after its life (%.2f s)" % [n, fx._life])
		check(fx._life < 12.0, "%s: a one-shot doesn't linger (%.2f s)" % [n, fx._life])
	var again := Fx.spawn("explosion", h, Vector3.ZERO)
	check(again == made["explosion"], "a finished one is reused (the pool)")
	check(Fx.spawn("no_such_effect", h, Vector3.ZERO) == null, "an unknown effect: nothing")
	var other := _host()
	var moved := Fx.spawn("dust_land", other, Vector3.ZERO)
	check(moved == made["dust_land"] and moved.get_parent() == other, "a pooled one moves to where it's wanted")
	h.free()
	other.free()
	check(not is_instance_valid(made["bolt_hit"]), "freed with its parent")
	var h2 := _host()
	check(Fx.spawn("bolt_hit", h2, Vector3.ZERO) != null, "the pool's freed ones skipped")
	h2.free()


func test_edits_and_reload_rebuild_live_effects() -> void:
	var h := _host()
	var boom := Fx.spawn("explosion", h, Vector3.ZERO)
	var mine := Fx.attach("mining_sparks", h)
	mine.emitting = false
	var n0 := (Fx.def("explosion")["emitters"] as Array).size()
	var d := Fx.def("explosion").duplicate(true)
	(d["emitters"] as Array).resize(2)
	d["emitters"][1]["amount"] = 5
	Fx.set_def("explosion", d)
	check(Fx.dirty, "an edit: unsaved")
	check_eq(boom._emitters.size(), 2, "the live explosion rebuilt (2 emitters)")
	check_eq((boom._emitters[1] as CPUParticles3D).amount, 5, "with the edited amount")
	var md := Fx.def("mining_sparks").duplicate(true)
	md["emitters"][0]["velocity"] = [1.0, 2.0]
	Fx.set_def("mining_sparks", md)
	check(is_equal_approx((mine._emitters[0] as CPUParticles3D).initial_velocity_max, 2.0), "the attached one too")
	check(not (mine._emitters[0] as CPUParticles3D).emitting, "and still off as it was")
	mine.emitting = true
	check((mine._emitters[0] as CPUParticles3D).emitting, "on again")
	Fx.reload_all()
	check_eq(boom._emitters.size(), n0, "reload: the file's definition back on the live one")
	check(not Fx.dirty, "reloaded: nothing unsaved")
	h.free()


func test_game_uses() -> void:
	var c := FakeCosmos.new()
	tree.root.add_child(c)
	CosmosBoom.at(c, Vector3(5, 0, 0), 20.0)
	var fx: Array = Fx.under(c.world)
	check(fx.size() == 1 and fx[0].effect == "explosion" and is_equal_approx(fx[0].scale_k, 2.0), "a ship's explosion: the effect, at twice the 10 m size")
	var b := CosmosBolt.new()
	b.cosmos = c
	b.space = true
	b.velocity = Vector3(0, 0, -100)
	b._impact(Vector3(1, 1, 1))
	check(Fx.under(c.world).any(func(f): return f.effect == "bolt_hit"), "a bolt striking in space: sparks")
	b.free()
	c.free()


func test_editor_builds_and_edits_live() -> void:
	var ed: Control = load(SCENE).instantiate()
	tree.root.add_child(ed)
	await tree.process_frame
	check(ed.find_child("TalosNav", true, false) != null, "the rail's there")
	var list: ItemList = ed.find_child("Effects", true, false)
	check(list != null and list.item_count == Fx.names().size(), "every effect listed")
	check_eq(ed.current, "explosion", "opens on the explosion")
	check(ed._fx != null and ed._fx.effect == "explosion", "it plays in the view")
	check(ed.find_child("Emitter0", true, false) != null, "its emitters' parameters")
	# An edit in the editor changes an explosion playing in the game.
	var h := _host()
	var boom := Fx.spawn("explosion", h, Vector3.ZERO)
	var p: FxParams = ed._params
	p.set_value(1, "amount", 7)
	check_eq((boom._emitters[1] as CPUParticles3D).amount, 7, "the game's explosion changed at once")
	check(ed.dirty, "unsaved")
	p.set_value(1, "amount", 9)
	ed._last_key = ""
	p.set_value(1, "colors", [[0.0, "#ff0000ff"], [1.0, "#00000000"]])
	ed.undo()
	check_eq((boom._emitters[1] as CPUParticles3D).amount, 9, "undo: the colours back")
	ed.undo()
	check_eq(int(Fx.val(Fx.def("explosion")["emitters"][1], "amount")), 22, "undo: the amount back (a drag is one step)")
	ed.redo()
	check_eq(int(Fx.val(Fx.def("explosion")["emitters"][1], "amount")), 9, "redo")
	ed.new_effect(true)
	check(ed.current == "explosion_copy" and Fx.has("explosion_copy"), "duplicated")
	ed.rename_effect("big boom")
	check(Fx.has("big_boom") and not Fx.has("explosion_copy"), "renamed")
	ed.delete_effect()
	check(not Fx.has("big_boom"), "deleted")
	ed.discard()
	check(not ed.dirty and not Fx.dirty, "discard: as saved")
	# The ramp and curve widgets build.
	ed.select("dust_land")
	(ed.find_child("Fold0", true, false) as Button).button_pressed = true
	check(ed.find_child("Ramp_0", true, false) != null and ed.find_child("Curve_0", true, false) != null, "a colour ramp and a scale curve")
	ed.free()
	h.free()
	var em: Control = load(SCENE).instantiate()
	em.set("embedded", true)
	tree.root.add_child(em)
	await tree.process_frame
	check(em.find_child("TalosNav", true, false) == null, "embedded: no rail")
	em.free()
	var ids := []
	for t in TalosNav.TOOLS:
		if t is Array:
			ids.append(t[0])
	check("fx" in ids and TalosNav.SCENES.has("fx") and "fx" in TalosNav.TOOL_IDS, "on Talos's rail")
	var me: GDScript = load("res://scripts/editor/mod_editor.gd")
	check("EFFECTS" in me.TABS and "fx" in me.TOOL_TABS, "a tab of the Mod Editor")


func test_save_into_a_mod() -> void:
	var before := FileAccess.get_file_as_string("res://data/effects.json")
	_mod = Mods.create("t")
	EditTarget.mod_id = _mod
	var d := Fx.def("dust_jet").duplicate(true)
	d["emitters"][0]["amount"] = 6
	Fx.set_def("dust_jet", d)
	check(Fx.save(), "saved")
	var p := Mods.files_dir(_mod) + "data/effects.json"
	check(FileAccess.file_exists(p), "into the mod (%s)" % p)
	var back = JSON.parse_string(FileAccess.get_file_as_string(p))
	check(back is Dictionary and int(back["dust_jet"]["emitters"][0]["amount"]) == 6, "with the edit")
	check(back is Dictionary and back.size() == Fx.names().size(), "and every other effect")
	check_eq(FileAccess.get_file_as_string("res://data/effects.json"), before, "not into the game")
	Fx.reload_all()
	check_eq(int(Fx.def("dust_jet")["emitters"][0]["amount"]), 6, "reload while making the mod: the mod's copy")


func test_live_tab_adds_a_kept_effect() -> void:
	var tab_script: GDScript = load("res://scripts/world/live/tabs/fx_tab.gd")
	check_eq(tab_script.TITLE, "Particles", "the tab's title")
	var thing := Node3D.new()
	thing.set_meta("edit_key", "test/fx")
	tree.root.add_child(thing)
	var part := Node3D.new()
	part.name = "Part"
	thing.add_child(part)
	check(tab_script.handles(part), "a 3D thing: effects can be added")
	var ed := FakeEd.new()
	ed.selected = part
	ed.anchor = thing
	ed.key = "test/fx"
	tree.root.add_child(ed)
	var tab: VBoxContainer = tab_script.new()
	ed.add_child(tab)
	tab.bind(ed)
	var fx: Node3D = tab.add_here("mining_sparks")
	check(fx != null and fx.get_parent() == part, "attached to what's picked")
	var sec := LiveEdits.section("test/fx", "fx")
	check(sec.get("added", []).size() == 1 and sec["added"][0]["path"] == "Part", "kept by LiveEdits")
	check(ed.edits > 0, "the editor told")
	tab_script.apply_edit(thing, sec)
	check_eq(Fx.under(part).size(), 1, "put back twice: still one")
	tab._edit("mining_sparks")
	(tab._params as FxParams).set_value(0, "amount", 11)
	check_eq((fx._emitters[0] as CPUParticles3D).amount, 11, "an edit in the tab changes it")
	# A new thing of that kind gets it back.
	var thing2 := Node3D.new()
	thing2.set_meta("edit_key", "test/fx")
	var part2 := Node3D.new()
	part2.name = "Part"
	thing2.add_child(part2)
	tree.root.add_child(thing2)
	tab_script.apply_edit(thing2, LiveEdits.section("test/fx", "fx"))
	check_eq(Fx.under(part2).size(), 1, "the same kind made again: the effect put back")
	tab.remove_added()
	check(not LiveEdits.data.has("test/fx"), "removed from the record")
	tab.unbind()
	ed.free()
	thing.free()
	thing2.free()


class FakeCosmos extends Node3D:
	var world: Node3D

	func _init() -> void:
		world = Node3D.new()
		add_child(world)


class FakeEd extends Node:
	var selected: Node
	var anchor: Node
	var key := ""
	var cosmos: Node
	var edits := 0

	func say(_t: String) -> void:
		pass

	func edited(_sec := "") -> void:
		edits += 1
