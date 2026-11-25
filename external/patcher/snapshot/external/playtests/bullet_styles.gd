extends SceneTree
## Every creature bullet style, flying, on black (a style sheet screenshot).
##   godot --path . -s external/playtests/bullet_styles.gd -- <out.png>
func _init():
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/bullets.png"
	await process_frame
	var bg := ColorRect.new(); bg.color = Color(0.01, 0.015, 0.03); bg.size = Vector2(1920, 1080); bg.z_index = -100
	root.add_child(bg)
	var w := Node2D.new(); root.add_child(w)
	var SM = load("res://scripts/space_monster.gd")
	var cols := {"orb": Color(0.55, 1.0, 0.45), "bubble": Color(1.0, 0.45, 0.75), "ink": Color(0.85, 0.3, 1.0), "spear": Color(1.0, 0.32, 0.15),
		"flame": Color(1.0, 0.45, 0.1), "ember": Color(1.0, 0.8, 0.3), "wave": Color(0.25, 0.6, 1.0), "ghost": Color(0.5, 1.0, 0.85)}
	var styles: Array = SM.Orb.STYLES
	var orbs := []
	for i in styles.size():
		for k in 3:
			var o = SM.Orb.new()
			o.style = styles[i]
			o.color = cols[styles[i]]
			o.velocity = Vector2(0, -40).rotated(-0.3 + k * 0.3)
			o.scale = Vector2(2.5, 2.5)
			o.position = Vector2(140 + i * 230, 520 + k * 150)
			w.add_child(o)
			orbs.append(o)
		var l := Label.new(); l.text = styles[i]; l.position = Vector2(100 + i * 230, 360); l.add_theme_font_size_override("font_size", 26)
		root.add_child(l)
	for f in 40: await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
