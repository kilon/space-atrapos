extends TestCase
## Music (res://music/, tools/music_gen.py) and the audio settings (master,
## music and effects volumes).


func test_music_tracks() -> void:
	var music: Node = tree.root.get_node("Music")
	for t in ["menu", "space", "surface"]:
		var s: AudioStream = music.stream(t)
		check(s is AudioStreamOggVorbis, "%s: a track" % t)
		if s:
			check(absf(s.get_length() - 120.0) < 1.0, "%s: two minutes (%.1f s)" % [t, s.get_length()])
			check(s.loop, "%s: loops" % t)
	check(music.stream("nonexistent") == null, "an unknown track: nothing")
	check(AudioServer.get_bus_index("Music") >= 0, "the Music bus")


func test_music_follows_the_scene() -> void:
	var music: Node = tree.root.get_node("Music")
	check_eq(music.track_for("res://main_menu.tscn"), "menu", "the main menu: the menu track")
	check_eq(music.track_for("res://main.tscn"), "space", "flying: the space track")
	check_eq(music.track_for("res://scenes/planet_surface.tscn"), "surface", "on a planet: the surface track")
	check_eq(music.track_for("res://unknown.tscn"), "", "elsewhere: no change")
	var was_auto: bool = music.auto
	music.auto = false
	music.play("space", 0.05)
	check_eq(music.current, "space", "playing space")
	check(music._players[music._active].stream == music.stream("space") and music._players[music._active].playing, "its player has it")
	music.play("surface", 0.05)
	check_eq(music.current, "surface", "a change crossfades to the new track")
	for i in 10:
		await tree.process_frame
	await tree.create_timer(0.2).timeout
	check(not music._players[1 - music._active].playing, "and the old one stops once faded")
	music.play("surface", 0.05)
	check_eq(music.current, "surface", "the same track again: no restart")
	music.stop(0.05)
	check_eq(music.current, "", "stop")
	music.auto = was_auto
	music._scene = null


func test_volume_settings() -> void:
	var old := {}
	for k in Settings.VOLUMES:
		old[k] = Settings.volume(k)
	for pair in [["master", "Master"], ["music", "Music"], ["sfx", "SFX"], ["voice", "Voice"]]:
		var i := AudioServer.get_bus_index(pair[1])
		Settings.set_volume(pair[0], 0.5)
		check(absf(AudioServer.get_bus_volume_db(i) - linear_to_db(0.5)) < 0.01, "%s volume sets the %s bus" % pair)
		Settings.set_volume(pair[0], 0.0)
		check(AudioServer.is_bus_mute(i), "%s at 0%% mutes it" % pair[0])
		Settings.set_volume(pair[0], 2.0)
		check_eq(Settings.volume(pair[0]), 1.0, "%s is capped at 100%%" % pair[0])
	# Saved and loaded.
	Settings.set_volume("music", 0.35)
	Settings.save_settings()
	Settings.music_volume = 1.0
	Settings.load_settings()
	check(absf(Settings.music_volume - 0.35) < 0.001, "the volumes are saved")
	for k in old:
		Settings.set_volume(k, old[k])
	Settings.save_settings()


func test_volume_sliders_in_the_menu() -> void:
	var menu: Control = load("res://main_menu.tscn").instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	check_eq(menu._volume_sliders.keys(), ["master", "music", "sfx", "voice"], "Master, Music, Sound effects and Voices sliders")
	var old: float = Settings.music_volume
	menu._volume_sliders["music"][0].value = 40.0
	check(absf(Settings.music_volume - 0.4) < 0.001, "the music slider sets the music volume")
	Settings.set_volume("music", old)
	menu.queue_free()
	await tree.process_frame


## The space sounds (sounds/space/, tools/sfx_space.py) and what plays them.
func test_space_sounds() -> void:
	var sfx: Node = tree.root.get_node("Sfx")
	var takes := {"laser": 4, "plasma": 3, "missile": 3, "enemy_laser": 4, "hit_shield": 4, "hit_hull": 4, "spark": 4,
		"boom_small": 3, "boom_big": 3, "ship_boom_small": 3, "ship_boom_medium": 3, "ship_boom_large": 2, "ship_boom_player": 1, "shields_down": 1, "afterburner": 2, "shield_boost": 2, "repair": 2,
		"rock_break": 3, "pickup": 3, "credits": 3, "dock": 1, "undock": 1, "jump": 2, "land": 1, "take_off": 1,
		"select": 2, "engine_loop": 1, "mining_loop": 1, "station_hum": 1, "gate_hum": 1}
	for k in takes:
		check_eq(sfx.takes("space/" + k).size(), takes[k], "space/%s: every take found" % k)
	# A looping sound sticks to its node and plays.
	var holder := Node2D.new()
	tree.root.add_child(holder)
	var hum = sfx.loop_at("space/station_hum", holder)
	await tree.process_frame
	check(hum is AudioStreamPlayer2D and hum.get_parent() == holder and hum.playing and hum.stream.loop, "a looping hum on its node")
	check(sfx.loop_at("space/nonexistent", holder) == null, "an unknown loop: nothing")
	holder.queue_free()
	await tree.process_frame


## In space: stations and gates hum, your ship has an engine; firing, being hit and explosions are heard.
func test_space_sounds_in_game() -> void:
	var m: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(m)
	for i in 5:
		await tree.process_frame
	var is_loop := func(node: Node, key: String) -> bool:
		return node.get_children().any(func(c): return c is AudioStreamPlayer2D and c.stream == tree.root.get_node("Sfx").takes(key)[0])
	var st: Node = tree.get_first_node_in_group("stations")
	check(st != null and is_loop.call(st, "space/station_hum"), "a station hums")
	var gate: Node = tree.get_first_node_in_group("gates")
	check(gate == null or is_loop.call(gate, "space/gate_hum"), "a jump gate hums")
	check(is_loop.call(m.ship, "space/engine_loop"), "your ship's engine")
	var fx: Node = tree.get_first_node_in_group("fx_layer")
	var heard := func(key: String) -> bool:
		return fx.get_children().any(func(c): return c is AudioStreamPlayer2D and c.stream in tree.root.get_node("Sfx").takes(key))
	m.ship.take_damage(5.0, m.ship.global_position + Vector2(50, 0))
	check(heard.call("space/hit_shield"), "a hit on your shields is heard")
	Effects.explosion(m.ship.global_position + Vector2(200, 0), 1.5)
	check(heard.call("space/boom_big"), "an explosion is heard")
	# Ships blowing up: a sound by size.
	check_eq(Effects.ship_sound(100.0), "space/ship_boom_small", "a fighter: the small ship explosion")
	check_eq(Effects.ship_sound(190.0), "space/ship_boom_medium", "a gunship: medium")
	check_eq(Effects.ship_sound(1450.0), "space/ship_boom_large", "a boss: large")
	var foe: Node = tree.get_first_node_in_group("enemies")
	if foe:
		foe.global_position = m.ship.global_position + Vector2(300, 0)
		var kind: String = Effects.ship_sound(foe.max_hull + foe.max_shields)
		foe.take_damage(100000.0, foe.global_position)
		check(heard.call(kind), "an enemy ship blowing up is heard (%s)" % kind)
	m.queue_free()
	for i in 3:
		await tree.process_frame


## Spoken dialogue (tools/voice_lines.py, scripts/voice.gd): every main-quest
## line and Kilon's lines have a recording; the dialogue box plays each line's
## own and stops when it closes.
func test_spoken_lines() -> void:
	var v: Node = tree.root.get_node("Voice")
	var missing := []
	var all := []
	for st in QuestData.STAGES:
		all.append_array(st.get("dialogue", []))
		all.append([QuestData.GIVER["name"], "Where it leads now: [b]%s[/b]." % st["objective"]])
	for k in ["offer", "accepted", "declined", "later", "done", "greeting", "farewell"]:
		all.append_array(QuestData.GIVER[k])
	for t in QuestData.GIVER["topics"]:
		all.append_array(t["lines"])
	for l in all:
		if v.recording(l[1], l[0]) == null:
			missing.append("%s: %s" % [l[0], l[1].left(40)])
	check(missing.is_empty(), "every story line is recorded (missing %d - run tools/voice_lines.py): %s" % [missing.size(), missing.slice(0, 3)])
	check(v.recording("The thread is in your hands.", "Kilon Alios") != null, "the Voices slider's sample")
	check_eq(v.key("[b]Hello[/b] ", "Kilon Alios"), v.key("Hello", "Kilon Alios"), "BBCode and spaces don't change the key")
	check(v.key("Hello", "Kilon Alios") != v.key("Hello", "Narrator"), "each speaker their own")
	check(v.recording("A line nobody ever said.", "Kilon Alios") == null, "an unrecorded line: none")
	var box: Control = preload("res://scripts/dialogue.gd").new()
	tree.root.add_child(box)
	var first: Array = QuestData.GIVER["offer"][0]
	box.play([first, ["Nobody", "Not recorded."]])
	check(v._player.playing and v._player.stream == v.recording(first[1], first[0]), "a line plays its own recording")
	box.advance()
	check(not v._player.playing, "an unrecorded line is silent")
	box._finish()
	check(not v._player.playing and v.speaking == "", "closing the conversation stops the voice")
	box.queue_free()
	tree.paused = false
	await tree.process_frame
