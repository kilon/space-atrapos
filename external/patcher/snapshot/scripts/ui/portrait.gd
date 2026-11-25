class_name Portrait
extends Control
## A comms-screen portrait: a person with a dinosaur head, wearing their star
## empire's dress. Fully procedural and deterministic from a seed string
## (same person every time you call them).
##
## Species: tyrannosaur, raptor, triceratops, parasaurolophus,
## pachycephalosaur, spinosaur, ankylosaur, dilophosaur, brachiosaur.

const SPECIES := ["tyrannosaur", "raptor", "triceratops", "parasaurolophus", "pachycephalosaur",
	"spinosaur", "ankylosaur", "dilophosaur", "brachiosaur"]
const SKINS := [Color(0.35, 0.55, 0.3), Color(0.55, 0.45, 0.3), Color(0.3, 0.45, 0.55), Color(0.6, 0.35, 0.25),
	Color(0.45, 0.5, 0.35), Color(0.5, 0.3, 0.45), Color(0.65, 0.58, 0.4), Color(0.3, 0.35, 0.3)]
const FIRST := ["Alkaios", "Thaleia", "Kreon", "Myrto", "Demetrios", "Ianthe", "Lykon", "Phaidra", "Sostratos", "Korinna",
	"Nikias", "Eudora", "Kallias", "Damaris", "Philon", "Xanthe", "Aristion", "Melitta", "Timon", "Chloris", "Hektor", "Ione"]
const EMPIRE_TITLES := {"athens": "Athenian", "sparta": "Spartan", "minoa": "Minoan", "mycenae": "Mycenaean", "ionia": "Ionian", "cyclades": "Cycladic", "independent": "Independent", "pirates": "Sea Peoples"}

var seed_text := "npc"
var empire := "athens"
var species := ""            # "" = from the seed
var person_name := ""
var _rng := RandomNumberGenerator.new()
var _t := 0.0


## Minoans are shown with their traced head portraits (external/images/minoan_npc_*,
## the sheets' head-details pictures): species -> name pool.
const MINOAN := ["gunner", "archer", "android"]
const MINOAN_FEMALE := ["archer"]
const MINOAN_NAMES := ["Minos", "Glaukos", "Deukalion", "Katreus", "Idomeneus", "Rhadamanthys", "Sarpedon", "Androgeos"]
const MINOAN_FEMALE_NAMES := ["Ariadne", "Phaedra", "Pasiphae", "Europa", "Britomartis", "Akakallis", "Diktynna", "Krete"]

var _minoan_tex: Texture2D


## Configure: who this is (seed), their empire, optional species / name.
const ANDROID_NAMES := ["Talos", "Chryseos", "Argyreos", "Kelmis", "Akmon", "Damnameneus", "Kaminos", "Kedalion"]


func setup(seed_: String, emp: String, sp := "", name_ := "") -> Portrait:
	seed_text = seed_
	empire = emp if emp != "" else "athens"
	_rng.seed = hash(seed_)
	_minoan_tex = null
	if empire == "minoa" and _portrait_texture("gunner") != null:
		if sp.begins_with("android"):
			sp = "android"   # (the rifle, bow and labrys androids share one face)
		species = sp if sp in MINOAN else MINOAN[_rng.randi() % MINOAN.size()]
		var pool: Array = MINOAN_FEMALE_NAMES if species in MINOAN_FEMALE else (ANDROID_NAMES if species == "android" else MINOAN_NAMES)
		person_name = name_ if name_ != "" else pool[_rng.randi() % pool.size()]
		_minoan_tex = _portrait_texture(species)
		if custom_minimum_size == Vector2.ZERO:
			custom_minimum_size = Vector2(200, 240)
		queue_redraw()
		return self
	species = sp if sp in SPECIES else SPECIES[_rng.randi() % SPECIES.size()]
	person_name = name_ if name_ != "" else FIRST[_rng.randi() % FIRST.size()]
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(200, 240)
	queue_redraw()
	return self


func _ready() -> void:
	if person_name == "":
		setup(seed_text, empire)
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # (the baked pictures, shown small)


var _redraw_t := 0.0

func _process(delta: float) -> void:
	_t += delta
	_redraw_t -= delta
	if _redraw_t <= 0.0:   # (30 times a second: a missions board shows nine of them)
		_redraw_t = 1.0 / 30.0
		if bake_layer == "":
			queue_redraw()


# --- Baking ----------------------------------------------------------------------------------
# Painting a portrait (dozens of gradient polygons) costs milliseconds, and a
# missions board shows nine, moving 30 times a second. So each person is
# painted once, off screen, into pictures: the backdrop and body, the head in
# a few frames (the jaw breathing at three openings, and a blink) and the
# scanlines and frame; the portrait then draws those, the head bobbing and
# tilting as before. Kept per person (seed, empire, species) for the session.

## Baking: which layer this (off-screen) portrait paints - "back", "head",
## "front"; "" for a normal one.
var bake_layer := ""
var _bake_open := 4.0
var _bake_blink := false
const BAKE_OPENS := [2.5, 4.0, 5.5]
static var _bakes := {}   # key -> {back, heads: [3 jaw openings + a blink], front, phase}; {} while baking


func _bake_key() -> String:
	return "%s|%s|%s" % [seed_text, empire, species]


func _baked() -> Dictionary:
	var b: Dictionary = _bakes.get(_bake_key(), {})
	return b if b.has("back") else {}


## The head frame now: the jaw opening nearest the breathing's, or the blink.
func _head_frame(phase: float) -> int:
	if fmod(_t + phase * 3.0, 4.0) <= 0.12:
		return 3
	var open := 4.0 + 2.0 * sin(_t * 2.0)
	return 0 if open < 3.25 else (1 if open < 4.75 else 2)


func _request_bake() -> void:
	var key := _bake_key()
	if _bakes.has(key) or not is_inside_tree():
		return
	if _bakes.size() > 64:
		_bakes.clear()   # (a long session: start over rather than grow)
	_bakes[key] = {}
	_bake(get_tree(), key, seed_text, empire, species, person_name)


static func _bake(tree: SceneTree, key: String, seed_: String, emp: String, sp: String, nm: String) -> void:
	var layers := [["back", 4.0, false]]
	for o in BAKE_OPENS:
		layers.append(["head", o, false])
	layers.append(["head", 4.0, true])
	layers.append(["front", 4.0, false])
	var vps := []
	for l in layers:
		var vp := SubViewport.new()
		vp.size = Vector2i(200, 240)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var p: Portrait = load("res://scripts/ui/portrait.gd").new()
		p.bake_layer = l[0]
		p._bake_open = l[1]
		p._bake_blink = l[2]
		p.setup(seed_, emp, sp, nm)
		p.custom_minimum_size = Vector2(200, 240)
		p.size = Vector2(200, 240)
		p.set_process(false)
		vp.add_child(p)
		tree.root.add_child(vp)
		vps.append(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var tex := []
	for vp in vps:
		var img: Image = vp.get_texture().get_image()
		vp.queue_free()
		if img == null or img.is_empty():
			continue   # (no renderer - headless: these people stay painted live)
		img.generate_mipmaps()
		tex.append(ImageTexture.create_from_image(img))
	if tex.size() < vps.size():
		_bakes[key] = {"failed": true}
		return
	var rng := RandomNumberGenerator.new()   # (the blink's phase: the draw's third random number)
	rng.seed = hash(seed_)
	rng.randi()
	rng.randi()
	_bakes[key] = {"back": tex[0], "heads": tex.slice(1, 5), "front": tex[5], "phase": rng.randf()}


## The traced head portrait of a Minoan species (baked at start-up).
static func _portrait_texture(sp: String) -> Texture2D:
	var tree := Engine.get_main_loop() as SceneTree
	var art: Node = tree.root.get_node_or_null("ProcArt") if tree else null
	return art.get_tex("npc_minoan_%s_portrait" % sp) if art else null


func species_name() -> String:
	if _minoan_tex:
		return {"gunner": "Minoan guard", "archer": "Minoan archer", "android": "Minoan android"}.get(species, "Minoan " + species.capitalize())
	return {"tyrannosaur": "Tyrannosaur", "raptor": "Raptor", "triceratops": "Ceratopsian", "parasaurolophus": "Hadrosaur",
		"pachycephalosaur": "Pachycephalosaur", "spinosaur": "Spinosaur", "ankylosaur": "Ankylosaur",
		"dilophosaur": "Dilophosaur", "brachiosaur": "Sauropod"}[species]


func _draw() -> void:
	if _minoan_tex:
		_draw_minoan()
		return
	var k := minf(size.x / 200.0, size.y / 240.0)
	var off := (size - Vector2(200, 240) * k) / 2.0
	var bob := sin(_t * 1.6) * 1.5
	var tilt := sin(_t * 0.7) * 0.03
	var ec: Color = Galaxy.empire_color(empire)
	# Baked: three pictures (the head in a few frames), drawn moving.
	var baked := _baked()
	if bake_layer == "" and not baked.is_empty():
		draw_set_transform(off, 0.0, Vector2(k, k))
		draw_texture(baked["back"], Vector2.ZERO)
		draw_set_transform(off + Vector2(0, bob) * k, tilt, Vector2(k, k))
		draw_texture(baked["heads"][_head_frame(baked["phase"])], Vector2.ZERO)
		draw_set_transform(off, 0.0, Vector2(k, k))
		draw_rect(Rect2(0, fmod(_t * 60.0, 240.0), 200, 3), Color(ec.lightened(0.5), 0.08))
		draw_texture(baked["front"], Vector2.ZERO)
		draw_set_transform(Vector2.ZERO)
		return
	if bake_layer == "":
		_request_bake()   # (drawn the slow way meanwhile - once or twice)
	var live := bake_layer == ""
	draw_set_transform(off, 0.0, Vector2(k, k))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var skin: Color = SKINS[rng.randi() % SKINS.size()]
	var belly := skin.lightened(0.35)
	var eye: Color = [Color(1.0, 0.75, 0.15), Color(0.9, 0.3, 0.15), Color(0.4, 0.9, 0.4), Color(0.5, 0.75, 1.0)][rng.randi() % 4]
	if live or bake_layer == "back":
		# Comms screen backdrop.
		Paint.gpoly(self, _rect(0, 0, 200, 240), Paint.radial(Vector2(100, 90), 170, [[0.0, ec.darkened(0.55)], [1.0, Color(0.02, 0.03, 0.06)]]))
		for i in 8:
			draw_line(Vector2(0, 30 + i * 28), Vector2(200, 30 + i * 28), Color(ec, 0.06), 1.0)
		# Body: shoulders in the empire's dress.
		_body(rng, ec, skin)
	if live or bake_layer == "head":
		# Neck and head.
		if live:
			draw_set_transform(off + Vector2(0, bob) * k, tilt, Vector2(k, k))
		if species == "brachiosaur":
			Paint.gpoly(self, PackedVector2Array([Vector2(82, 200), Vector2(92, 120), Vector2(104, 60), Vector2(122, 62), Vector2(118, 128), Vector2(120, 200)]),
				Paint.linear(Vector2(80, 0), Vector2(125, 0), [[0.0, skin.lightened(0.1)], [1.0, skin.darkened(0.3)]]), Color(0.05, 0.05, 0.05), 2.0)
		else:
			Paint.gpoly(self, PackedVector2Array([Vector2(74, 205), Vector2(80, 150), Vector2(124, 150), Vector2(130, 205)]),
				Paint.linear(Vector2(74, 0), Vector2(130, 0), [[0.0, skin.lightened(0.05)], [1.0, skin.darkened(0.35)]]), Color(0.05, 0.05, 0.05), 2.0)
		_head(rng, skin, belly, eye)
		_accessory(rng, ec)
		draw_set_transform(off, 0.0, Vector2(k, k))
	if live or bake_layer == "front":
		# Scanlines and a frame.
		if live:
			draw_rect(Rect2(0, fmod(_t * 60.0, 240.0), 200, 3), Color(ec.lightened(0.5), 0.08))
		for i in 60:
			draw_line(Vector2(0, i * 4), Vector2(200, i * 4), Color(0, 0, 0, 0.12), 1.0)
		draw_rect(Rect2(1, 1, 198, 238), Color(ec, 0.8), false, 2.0)
	draw_set_transform(Vector2.ZERO)


func _rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


func _body(rng: RandomNumberGenerator, ec: Color, _skin: Color) -> void:
	var cloth: Color
	var trim: Color
	match empire:
		"athens": cloth = Color(0.88, 0.89, 0.92); trim = Color(0.2, 0.45, 0.9)
		"sparta": cloth = Color(0.7, 0.45, 0.2); trim = Color(0.8, 0.1, 0.08)
		"minoa": cloth = Color(0.15, 0.6, 0.6); trim = Color(0.9, 0.55, 0.2)
		"mycenae": cloth = Color(0.85, 0.68, 0.28); trim = Color(0.5, 0.18, 0.12)
		"ionia": cloth = Color(0.16, 0.24, 0.62); trim = Color(0.95, 0.78, 0.35)
		"cyclades": cloth = Color(0.92, 0.9, 0.85); trim = Color(0.15, 0.75, 0.75)
		"independent": cloth = Color(0.45, 0.48, 0.5); trim = Color(0.3, 0.8, 0.5)
		_: cloth = Color(0.35, 0.18, 0.15); trim = Color(0.85, 0.75, 0.6)
	var sh := PackedVector2Array([Vector2(10, 240), Vector2(22, 196), Vector2(60, 180), Vector2(140, 180), Vector2(178, 196), Vector2(190, 240)])
	Paint.gpoly(self, sh, Paint.linear(Vector2(0, 180), Vector2(0, 240), [[0.0, cloth.lightened(0.15)], [1.0, cloth.darkened(0.35)]]), Color(0.05, 0.05, 0.05), 2.0)
	# Collar / cuirass detail.
	draw_polyline(PackedVector2Array([Vector2(60, 182), Vector2(100, 214), Vector2(140, 182)]), trim, 5.0, true)
	match empire:
		"athens":   # owl brooch
			draw_circle(Vector2(52, 205), 9, Color(0.95, 0.78, 0.3))
			draw_circle(Vector2(49, 203), 2.5, Color(0.1, 0.1, 0.1))
			draw_circle(Vector2(55, 203), 2.5, Color(0.1, 0.1, 0.1))
		"sparta":   # red cloak over a shoulder and a lambda
			Paint.gpoly(self, PackedVector2Array([Vector2(140, 182), Vector2(178, 196), Vector2(190, 240), Vector2(150, 240)]), Color(0.75, 0.08, 0.06), Color(0.05, 0.05, 0.05), 2.0)
			draw_polyline(PackedVector2Array([Vector2(88, 232), Vector2(100, 212), Vector2(112, 232)]), Color(0.9, 0.15, 0.1), 4.0)
		"minoa":    # labrys pendant
			draw_line(Vector2(100, 214), Vector2(100, 234), Color(0.95, 0.8, 0.3), 3.0)
			for sx in [-1.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([Vector2(100, 220), Vector2(100 + sx * 10, 214), Vector2(100 + sx * 10, 230)]), Color(0.95, 0.8, 0.3))
		"mycenae":  # gold plates
			for i in 3:
				draw_line(Vector2(40, 205 + i * 10), Vector2(160, 205 + i * 10), Color(0.6, 0.45, 0.15), 2.0)
		"ionia":    # Ionic volute brooch
			for sx in [-1.0, 1.0]:
				draw_arc(Vector2(100 + sx * 9, 222), 6, 0, TAU * 0.85, 12, Color(0.95, 0.78, 0.35), 2.5)
			draw_line(Vector2(91, 216), Vector2(109, 216), Color(0.95, 0.78, 0.35), 3.0)
		_:          # Sea Peoples: crossed straps
			draw_line(Vector2(30, 200), Vector2(170, 240), trim, 4.0)
			draw_line(Vector2(170, 200), Vector2(30, 240), trim, 4.0)
	draw_line(Vector2(24, 195), Vector2(60, 181), Color(ec.lightened(0.3), 0.6), 2.0)


## The head: a common snout / skull / jaw build, shaped per species, facing
## three-quarters to the right.
func _head(rng: RandomNumberGenerator, skin: Color, belly: Color, eye: Color) -> void:
	var line := Color(0.05, 0.05, 0.05)
	var dark := skin.darkened(0.35)
	var long := 1.0
	var tall := 1.0
	match species:
		"raptor", "spinosaur": long = 1.35; tall = 0.8
		"tyrannosaur": long = 1.1; tall = 1.15
		"brachiosaur": long = 0.8; tall = 0.85
		"pachycephalosaur": long = 0.85; tall = 1.05
		"ankylosaur": long = 0.9; tall = 0.9
	var cy := 112.0 if species != "brachiosaur" else 66.0
	var cx := 92.0 if species != "brachiosaur" else 104.0
	var sk := 1.0 if species != "brachiosaur" else 0.7
	var p := func(x: float, y: float) -> Vector2: return Vector2(cx + x * long * sk, cy + y * tall * sk)
	# Frill behind the head (ceratopsian / dilophosaur).
	if species == "triceratops":
		var fr := PackedVector2Array()
		for i in 15:
			var a := PI * 0.55 + PI * 1.1 * i / 14.0
			fr.append(p.call(-28 + cos(a) * 62, -18 + sin(a) * 66))
		fr.append(p.call(-10, 30))
		Paint.gpoly(self, fr, Paint.radial(p.call(-28, -18), 66, [[0.0, skin.darkened(0.1)], [0.8, skin.lightened(0.15)], [1.0, Color(0.85, 0.5, 0.25)]]), line, 2.0)
		for i in 7:
			var a := PI * 0.6 + PI * 1.0 * i / 6.0
			draw_circle(p.call(-28 + cos(a) * 58, -18 + sin(a) * 60), 4, Color(0.95, 0.85, 0.6))
	if species == "dilophosaur":
		var fr := PackedVector2Array()
		for i in 13:
			var a := PI * 0.5 + PI * i / 12.0
			fr.append(p.call(-30 + cos(a) * 52, 18 + sin(a) * 50))
		Paint.gpoly(self, fr, Paint.radial(p.call(-30, 18), 52, [[0.0, Color(0.95, 0.85, 0.3)], [0.6, Color(0.9, 0.35, 0.2)], [1.0, Color(0.3, 0.6, 0.4)]]), line, 2.0)
	# Skull + snout (upper jaw).
	var upper := PackedVector2Array([p.call(-38, -30), p.call(-8, -44), p.call(30, -34), p.call(62, -20), p.call(78, -6),
		p.call(76, 6), p.call(30, 6), p.call(-20, 14), p.call(-42, 6)])
	Paint.gpoly(self, upper, Paint.linear(p.call(0, -44), p.call(0, 14), [[0.0, skin.lightened(0.12)], [0.7, skin], [1.0, dark]]), line, 2.0)
	# Lower jaw (mouth slightly open, breathing).
	var open := _bake_open if bake_layer == "head" else 4.0 + 2.0 * sin(_t * 2.0)
	var lower := PackedVector2Array([p.call(-36, 8), p.call(30, 8 + open), p.call(70, 10 + open), p.call(66, 22 + open), p.call(20, 30), p.call(-30, 26)])
	Paint.gpoly(self, lower, Paint.linear(p.call(0, 8), p.call(0, 30), [[0.0, belly], [1.0, belly.darkened(0.25)]]), line, 2.0)
	# Teeth for the meat-eaters.
	if species in ["tyrannosaur", "raptor", "spinosaur", "dilophosaur"]:
		for i in 7:
			var x := -6.0 + i * 11.0
			draw_colored_polygon(PackedVector2Array([p.call(x, 5), p.call(x + 4, 13 + open * 0.5), p.call(x + 8, 5)]), Color(0.97, 0.95, 0.85))
	# Beak (herbivores).
	if species in ["triceratops", "parasaurolophus", "ankylosaur"]:
		draw_colored_polygon(PackedVector2Array([p.call(66, -10), p.call(84, 0), p.call(66, 12)]), Color(0.3, 0.25, 0.2))
	# Eye with a brow ridge and a slow blink.
	var phase := rng.randf()
	var blink := (0.15 if _bake_blink else 1.0) if bake_layer == "head" else (1.0 if fmod(_t + phase * 3.0, 4.0) > 0.12 else 0.15)
	var ep: Vector2 = p.call(0, -20)
	draw_circle(ep, 8.0, Color(0.05, 0.05, 0.05))
	Paint.gellipse(self, ep, 6.5, 6.5 * blink, Paint.radial(ep + Vector2(-2, -2), 7, [[0.0, eye.lightened(0.3)], [1.0, eye.darkened(0.3)]]))
	if blink > 0.5:
		draw_line(ep + Vector2(0, -5), ep + Vector2(0, 5), Color(0.05, 0.05, 0.05), 2.5)
		draw_circle(ep + Vector2(-2, -3), 1.6, Color(1, 1, 1, 0.9))
	draw_line(p.call(-10, -30), p.call(14, -27), dark.darkened(0.3), 4.0, true)
	# Nostril and texture spots.
	draw_circle(p.call(66, -12), 2.5, Color(0.05, 0.05, 0.05))
	for i in 6:
		draw_circle(p.call(rng.randf_range(-30, 40), rng.randf_range(-36, 0)), rng.randf_range(1.5, 3.5), Color(dark, 0.5))
	# Species features.
	match species:
		"triceratops":
			for h in [[p.call(60, -18), Vector2(14, -20), 0.6], [p.call(-4, -40), Vector2(26, -44), 1.0], [p.call(14, -42), Vector2(30, -40), 1.0]]:
				var b: Vector2 = h[0]
				var d: Vector2 = h[1] * float(h[2])
				draw_colored_polygon(PackedVector2Array([b + Vector2(-6, 2), b + d, b + Vector2(6, 2)]), Color(0.95, 0.9, 0.75))
				draw_polyline(PackedVector2Array([b + Vector2(-6, 2), b + d, b + Vector2(6, 2)]), line, 1.5, true)
		"parasaurolophus":
			var crest := PackedVector2Array([p.call(-6, -40), p.call(-50, -78), p.call(-62, -74), p.call(-20, -34)])
			Paint.gpoly(self, crest, Paint.linear(p.call(-6, -40), p.call(-60, -76), [[0.0, skin], [1.0, Color(0.85, 0.45, 0.25)]]), line, 2.0)
		"pachycephalosaur":
			Paint.gellipse(self, p.call(-12, -42), 34, 22, Paint.radial(p.call(-20, -52), 34, [[0.0, Color(0.95, 0.9, 0.8)], [1.0, skin.darkened(0.1)]]), line, 2.0)
			for i in 7:
				var a := PI + PI * i / 6.0
				draw_circle(p.call(-12 + cos(a) * 36, -40 + sin(a) * 22 + 10), 3.5, dark)
		"spinosaur":
			var sail := PackedVector2Array([p.call(-36, -28), p.call(-26, -60), p.call(-10, -66), p.call(8, -58), p.call(14, -38)])
			Paint.gpoly(self, sail, Paint.linear(p.call(0, -66), p.call(0, -30), [[0.0, Color(0.9, 0.35, 0.25)], [1.0, skin]]), line, 2.0)
		"ankylosaur":
			for i in 5:
				var c: Vector2 = p.call(-30 + i * 14, -38 + abs(i - 2) * 3)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-6, 4), c + Vector2(0, -8), c + Vector2(6, 4)]), dark)
			draw_colored_polygon(PackedVector2Array([p.call(-40, -10), p.call(-56, -20), p.call(-42, 0)]), dark)
		"dilophosaur":
			for sx in [0.0, 12.0]:
				var cr := PackedVector2Array([p.call(-20 + sx, -38), p.call(-6 + sx, -66), p.call(30 + sx, -44)])
				Paint.gpoly(self, cr, Color(0.9, 0.3, 0.2), line, 1.5)
		"raptor":
			for i in 6:
				var b: Vector2 = p.call(-30 + i * 4, -30 - i * 2)
				draw_line(b, b + Vector2(-18, -14 - i * 2), Color(0.6, 0.3, 0.6) if i % 2 == 0 else Color(0.3, 0.5, 0.7), 4.0, true)
		"tyrannosaur":
			draw_colored_polygon(PackedVector2Array([p.call(-14, -38), p.call(-6, -48), p.call(4, -38)]), dark)


## Empire headwear.
func _accessory(rng: RandomNumberGenerator, ec: Color) -> void:
	var top := Vector2(92, 66) if species != "brachiosaur" else Vector2(104, 34)
	match empire:
		"athens":   # olive wreath
			for i in 9:
				var a := PI * 1.05 + PI * 0.9 * i / 8.0
				var pt := top + Vector2(cos(a) * 36, sin(a) * 12 + 10)
				Paint.gellipse(self, pt, 6, 3, Color(0.45, 0.65, 0.3))
		"sparta":   # horsehair crest
			var crest := PackedVector2Array()
			for i in 12:
				var a := PI + PI * i / 11.0
				crest.append(top + Vector2(cos(a) * 46 - 10, sin(a) * 34 + 6))
			for i in range(11, -1, -1):
				var a := PI + PI * i / 11.0
				crest.append(top + Vector2(cos(a) * 36 - 10, sin(a) * 24 + 6))
			Paint.gpoly(self, crest, Paint.linear(top + Vector2(0, -30), top + Vector2(0, 10), [[0.0, Color(0.95, 0.2, 0.12)], [1.0, Color(0.5, 0.05, 0.04)]]), Color(0.05, 0.05, 0.05), 1.5)
		"minoa":    # gold hoop earring and a flower
			draw_arc(top + Vector2(-22, 70), 7, 0, TAU, 16, Color(0.95, 0.8, 0.3), 2.5, true)
			for i in 5:
				draw_circle(top + Vector2(10, 4) + Vector2.from_angle(TAU * i / 5.0) * 5, 3.5, Color(0.95, 0.5, 0.6))
			draw_circle(top + Vector2(10, 4), 2.5, Color(1, 0.9, 0.3))
		"mycenae":  # boar-tusk helmet band
			for i in 4:
				var y := top.y - 12 + i * 6
				draw_line(Vector2(top.x - 40, y), Vector2(top.x + 20, y - 4), Color(0.95, 0.92, 0.8), 4.0, true)
		_:          # Sea Peoples feather crown
			for i in 9:
				var x := top.x - 40 + i * 9
				Paint.gpoly(self, PackedVector2Array([Vector2(x, top.y + 8), Vector2(x + 3, top.y - 26 - (i % 3) * 5), Vector2(x + 7, top.y + 8)]),
					Color(0.9, 0.85, 0.75) if i % 2 == 0 else ec)
			draw_line(Vector2(top.x - 42, top.y + 8), Vector2(top.x + 42, top.y + 8), Color(0.6, 0.2, 0.1), 5.0)


## Minoan contact: the traced head portrait on a comms backdrop in the
## Minoan colours, breathing gently.
func _draw_minoan() -> void:
	var ec: Color = Galaxy.empire_color(empire)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05))
	var c := size * Vector2(0.5, 0.42)
	for i in 10:
		draw_circle(c, size.x * (0.62 - i * 0.05), Color(ec.darkened(0.5), 0.12))
	for i in int(size.y / 14.0):
		draw_line(Vector2(0, i * 14), Vector2(size.x, i * 14), Color(ec, 0.05), 1.0)
	var ts := _minoan_tex.get_size()
	var k := minf(size.x * 1.02 / ts.x, size.y * 1.0 / ts.y)
	var bob := sin(_t * 1.4) * 1.5
	var dst := ts * k
	draw_texture_rect(_minoan_tex, Rect2(Vector2((size.x - dst.x) / 2.0, size.y - dst.y + 2.0 + bob), dst), false)
	# Comms scan line and frame.
	var sy := fmod(_t * 40.0, size.y)
	draw_line(Vector2(0, sy), Vector2(size.x, sy), Color(ec, 0.12), 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(ec, 0.6), false, 2.0)
