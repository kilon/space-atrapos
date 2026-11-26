extends TestCase
## The CRT filter (CrtFilter, shaders/crt.gdshader) and its settings: off in
## normal play by default, on in attract mode by default, every shader
## parameter tunable on its own settings page.


func _crt_filter() -> CrtFilter:
	for n in tree.root.get_children():
		if n is CrtFilter:
			return n
	return null


func test_crt_defaults_and_saving() -> void:
	var saved := {"on": Settings.crt_on, "attract": Settings.crt_attract, "crt": Settings.crt.duplicate()}
	check(not Settings.CRT_ON_DEFAULT and Settings.CRT_ATTRACT_DEFAULT, "off by default, on in attract mode by default")
	# Every parameter is a uniform of the shader, with its default as the shader's.
	var shader: Shader = load("res://shaders/crt.gdshader")
	var uniforms := {}
	for u in shader.get_shader_uniform_list():
		uniforms[u["name"]] = true
	var defaults := {}   # (from the code: "uniform float x = 0.5;")
	var re := RegEx.create_from_string("uniform float (\\w+) = ([0-9.]+);")
	for m in re.search_all(shader.code):
		defaults[m.get_string(1)] = float(m.get_string(2))
	for p in Settings.CRT_PARAMS:
		check(uniforms.has(p[0]), "%s is a shader parameter" % p[0])
		check(p[2] <= p[5] and p[5] <= p[3], "%s: its default is in its range" % p[0])
		check(is_equal_approx(float(defaults.get(p[0], -1.0)), p[5]), "%s: the same default as the shader" % p[0])
	for u in uniforms:
		if u != "screen_tex":
			check(Settings.CRT_PARAMS.any(func(p): return p[0] == u), "the shader's %s is in the settings" % u)
	# Saved and loaded; clamped to the range.
	Settings.set_crt_switch(false, true)
	Settings.set_crt("scanline_strength", 0.7)
	Settings.set_crt("curvature", 5.0)
	check_eq(Settings.crt["curvature"], 0.2, "values are clamped")
	Settings.save_settings()
	Settings.crt_on = false
	Settings.crt["scanline_strength"] = 0.0
	Settings.load_settings()
	check(Settings.crt_on and is_equal_approx(Settings.crt["scanline_strength"], 0.7), "the switches and the look are saved")
	Settings.reset_crt()
	check(is_equal_approx(Settings.crt["scanline_strength"], 0.38) and Settings.crt_on, "Default Look: the sliders, not the switches")
	Settings.crt_on = saved["on"]
	Settings.crt_attract = saved["attract"]
	Settings.crt = saved["crt"]
	Settings.save_settings()


func test_crt_filter_shows_when_wanted() -> void:
	var f := _crt_filter()
	check(f != null, "Settings put the filter on the root")
	if f == null:
		return
	check(f.layer == 127, "over everything but the scene-change fades")
	var saved := [Settings.crt_on, Settings.crt_attract, Settings.crt_preview, AttractMode.active]
	Settings.crt_on = false
	Settings.crt_preview = false
	AttractMode.active = false
	await tree.process_frame
	check(not f.visible, "off: not shown")
	Settings.crt_on = true
	await tree.process_frame
	check(f.visible, "always on: shown")
	Settings.crt_on = false
	Settings.crt_attract = true
	AttractMode.active = true
	await tree.process_frame
	check(f.visible, "in attract mode: shown")
	Settings.crt_attract = false
	await tree.process_frame
	check(not f.visible, "unless switched off for attract mode")
	AttractMode.active = false
	Settings.crt_preview = true
	await tree.process_frame
	check(f.visible, "the settings page previews it")
	var old: float = Settings.crt["vignette"]
	Settings.crt["vignette"] = 0.77
	await tree.process_frame
	check(is_equal_approx(float(f.rect.material.get_shader_parameter("vignette")), 0.77), "the settings reach the shader")
	Settings.crt["vignette"] = old
	Settings.crt_on = saved[0]
	Settings.crt_attract = saved[1]
	Settings.crt_preview = saved[2]
	AttractMode.active = saved[3]


func test_crt_settings_page() -> void:
	var saved := {"on": Settings.crt_on, "crt": Settings.crt.duplicate()}
	var menu: Control = load("res://main_menu.tscn").instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	check(menu.settings_panel.find_child("CrtRow", true, false) != null, "a CRT filter row on the settings page")
	check_eq(menu._crt_sliders.size(), Settings.CRT_PARAMS.size(), "a slider for every parameter")
	menu._open_settings()
	menu._crt_check.button_pressed = true
	check(Settings.crt_on, "its switch turns it on")
	menu._crt_check.button_pressed = false
	check(not Settings.crt_on, "and off")
	menu._open_crt()
	check(menu.crt_panel.visible and not menu.settings_panel.visible, "Tune opens its own page")
	check(Settings.crt_preview, "with a live preview")
	menu._crt_sliders["mask_strength"][0].value = 0.3
	check(is_equal_approx(Settings.crt["mask_strength"], 0.3), "a slider sets its parameter")
	check_eq(menu._crt_sliders["mask_strength"][1].text, "30%", "and shows it")
	check(not menu._crt_sliders["mask_strength"][2].disabled, "its reset button lights up")
	menu._crt_sliders["mask_strength"][2].pressed.emit()
	check(is_equal_approx(Settings.crt["mask_strength"], 0.14), "reset: back to the default")
	menu._close_crt()
	check(menu.settings_panel.visible and not menu.crt_panel.visible and not Settings.crt_preview, "Back: the settings page, no preview")
	menu.queue_free()
	await tree.process_frame
	Settings.crt_on = saved["on"]
	Settings.crt = saved["crt"]
	Settings.save_settings()
