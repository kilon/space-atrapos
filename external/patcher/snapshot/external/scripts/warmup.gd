extends Node2D
## Shader / pipeline warm-up. The first time each kind of visual is drawn,
## the GPU compiles a pipeline for it, causing a one-off hitch (50-120 ms)
## the first time you fly near an asteroid, station, explosion, etc.
## This node draws one of everything, practically invisible, for a few frames
## at game start, then removes itself.

const FRAMES := 4

var _frames := 0
## Once a run: the pipelines stay compiled (a jump, taking off - the space
## scene built again - needn't draw it all again: ~30 ms of its first frame).
static var done := false


func _ready() -> void:
	if done:
		queue_free()
		return
	done = true
	# (Dark as well as clear: pictures drawn with premultiplied alpha - the
	# rocks, ShaderCache - ignore a modulate's alpha, and showed at full
	# brightness on the title screen for the warm-up's frames.)
	modulate = Color(0.02, 0.02, 0.02, 0.02)
	z_index = -100

	# The backdrop shaders - a planet, a star, a nebula: tens of ms each to
	# compile the first time on a machine (kept on disk after that) - here,
	# one a frame, not in the frames a new game's system is built in.
	# (Drawn as space draws them: a planet and a nebula each through its
	# ShaderCache picture - their own pipelines - and a planet and a star live.)
	var pl := PlanetGen.make(PlanetGen.generate(PlanetGen.TEMPLATES.keys()[0], 1), 24.0)
	pl.position = Vector2(-300, 90)
	_add_inert(pl)
	# The near-death screen's static (DamageScreen): its shader compiled now, not on the first bad hit.
	var ds := ColorRect.new()
	ds.size = Vector2(8, 8)
	ds.position = Vector2(-320, 60)
	var dm := ShaderMaterial.new()
	dm.shader = DamageScreen.shader()
	dm.set_shader_parameter("k", 0.01)
	ds.material = dm
	_add_inert(ds)
	var pc := PlanetGen.make(PlanetGen.generate(PlanetGen.TEMPLATES.keys()[0], 2), 24.0, PlanetGen.DISK, true)
	pc.position = Vector2(-270, 90)
	_add_inert(pc, true)
	var st := StarGen.make(StarGen.generate(StarGen.TEMPLATES.keys()[0], 1), 4.0)
	st.position = Vector2(-240, 90)
	_add_inert(st)
	var nb := NebulaGen.make(NebulaGen.generate(NebulaGen.TEMPLATES.keys()[0], 1), 24.0)
	nb.position = Vector2(-180, 90)
	_add_inert(ShaderCache.wrap(nb, 4.0, 64.0, CanvasItemMaterial.BLEND_MODE_ADD), true)

	# The nav beacon: its trails' shader (nav_trail) and its additive fronts.
	var nav := NavBeacon.new()
	nav.position = Vector2(-120, 90)
	_add_inert(nav)

	# The health gauge (the HUD's, on foot too): its liquid fill and shield ring shaders.
	var gauge := HealthGauge.new()
	gauge.silhouette = ProcArt.sprite("ship_player")
	gauge.position = Vector2(-420, -120)
	gauge.scale = Vector2(0.3, 0.3)
	_add_inert(gauge)

	# Asteroids of every kind.
	var x := -300.0
	for kind in Asteroid.KINDS:
		var rock := Asteroid.new().setup({"kind": kind, "position": [x, 0], "radius": 40.0,
			"ore_total": 4, "ore_left": 4, "seed": 1})
		rock.targeted = true
		_add_inert(rock)
		x += 120.0

	# A station.
	var station: Node2D = preload("res://scenes/station.tscn").instantiate()
	station.radius = 60.0
	_add_inert(station)

	# The lock-on outline shader (compiled now, not on the first click).
	var spr := Sprite2D.new()
	spr.texture = EnemyTypes.texture(EnemyTypes.FALLBACK)
	spr.position = Vector2(x, 0)
	spr.scale = Vector2(0.3, 0.3)
	var outline := TargetOutline.new()
	outline.texture = spr.texture
	outline.on = true
	spr.add_child(outline)
	_add_inert(spr)
	x += 120.0

	# Projectiles of every style.
	for style in ["laser", "plasma", "missile"]:
		var p := Projectile.new()
		p.style = style
		p.position = Vector2(x, 40)
		_add_inert(p)
		x += 40.0

	# Shields (player and hostile colours use the same shader).
	var shield := ShieldEffect.new().setup(Vector2(120, 160), Color(0.3, 0.75, 1.0), Color.WHITE)
	add_child(shield)
	shield.hit(global_position + Vector2(100, 0))

	# Pickups / item icons.
	for id in ["credits", "iron_ore", "data_core"]:
		var pk := Pickup.new()
		pk.item_id = id
		pk.position = Vector2(x, -40)
		_add_inert(pk)
		x += 40.0

	# Particles: glowing (explosions/sparks) and solid (rock debris).
	var glow := Effects._particles(8, 0.3, 10.0, 20.0, 1.0, 2.0)
	_add_inert(glow)
	var solid := Effects._particles(8, 0.3, 10.0, 20.0, 1.0, 2.0)
	solid.material = null
	_add_inert(solid)


## Adds a node for drawing only: no processing, and out of gameplay groups -
## one a frame (all of them in one frame: ~90 ms the first time), each drawn
## for FRAMES frames.
var _queue: Array = []
var _running := {}   # (nodes that keep processing: a ShaderCache sets its picture up in _process)
func _add_inert(node: Node, running := false) -> void:
	_queue.append(node)
	if running:
		_running[node] = true


func _process(_delta: float) -> void:
	if not _queue.is_empty():
		var node: Node = _queue.pop_front()
		add_child(node)
		if not _running.has(node):
			node.process_mode = Node.PROCESS_MODE_DISABLED
		for group in node.get_groups():
			node.remove_from_group(group)
		_frames = 0
		return
	_frames += 1
	if _frames >= FRAMES:
		queue_free()


func _exit_tree() -> void:
	for n in _queue:   # (never added: freed with it)
		if is_instance_valid(n):
			n.free()
	_queue.clear()
