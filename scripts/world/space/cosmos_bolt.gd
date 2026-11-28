class_name CosmosBolt
extends Node3D
## A rifle bolt on a planet in the 3D game: a streak of light flying straight,
## hitting the first creature, pirate or walker (whoever it's aimed at: `side`
## "player" hits animals and pirates, "enemy" hits you) in its way, or the
## ground. Checked as a segment each frame - no tunnelling at 150 m/s.

const SPEED := 150.0
const LIFE := 1.4
const SPACE_SPEED := 900.0       # (ships' lasers in space)
const PULSE_SPEED := 2600.0      # (yours: fast, on top of your ship's own speed - easy to land on a raider)
const PULSE_LIFE := 1.5
const PULSE_SLACK := 3.0         # m: your bolts' hits a little forgiving (a ship's outline isn't a ball)
const SPACE_LIFE := 2.6
const GLOW := preload("res://shaders/world/glow.gdshader")

static var _mesh: QuadMesh
static var _mats := {}

var side := "player"
var damage := 20.0
var cosmos: Node
var velocity := Vector3.ZERO
var space := false
var tint := Color(0, 0, 0, 0)    # (a gun's own colour; none: the side's)
var orb := false                 # (a monster's slow orb: big, lives long)
var life := 0.0                  # s (0: the kind's own)
var slack := 0.0                 # m added to what it hits' reach
var big := false                 # (a station's heavy gun's: drawn bigger)
var _t := 0.0
var _streak: MeshInstance3D


## `speed` (> 0): slower orbs (the monsters': bigger, longer-lived), `col` their colour.
static func fire(c: Node, from: Vector3, dir: Vector3, who: String, dmg: float, in_space := false, speed := 0.0, col := Color(0, 0, 0, 0)) -> CosmosBolt:
	var b := CosmosBolt.new()
	b.cosmos = c
	b.side = who
	b.damage = dmg
	b.space = in_space
	b.velocity = dir.normalized() * (speed if speed > 0.0 else (SPACE_SPEED if in_space else SPEED))
	if speed > 0.0:
		b.orb = true
		b.tint = col
	c.world.add_child(b)
	b.global_position = from
	return b


func _ready() -> void:
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2(1.1, 1.1)
	if not _mats.has(side):
		var m := ShaderMaterial.new()
		m.shader = GLOW
		m.set_shader_parameter("tint", Color(0.4, 0.9, 1.0) if side == "player" else Color(1.0, 0.35, 0.2))
		m.set_shader_parameter("intensity", 3.0)
		m.set_shader_parameter("core", 0.3)
		_mats[side] = m
	var mi := MeshInstance3D.new()   # (one glow: a bolt is one draw)
	mi.mesh = _mesh
	if tint.a > 0.0:
		var key := tint.to_html()
		if not _mats.has(key):
			var m := ShaderMaterial.new()
			m.shader = GLOW
			m.set_shader_parameter("tint", tint)
			m.set_shader_parameter("intensity", 3.0)
			m.set_shader_parameter("core", 0.3)
			_mats[key] = m
		mi.material_override = _mats[key]
	if space:
		mi.scale = Vector3.ONE * (16.0 if orb else (11.0 if big else 5.0))
	if mi.material_override == null:
		mi.material_override = _mats[side]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.95 else Vector3.RIGHT)


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_t += delta
	var a := global_position
	var b := a + velocity * delta
	if _t > (12.0 if orb else (life if life > 0.0 else (SPACE_LIFE if space else LIFE))):
		queue_free()
		return
	if step(a, b):
		_impact(b)
		queue_free()
		return
	global_position = b


## Where it struck: a flash and sparks (the effects "bolt_hit" in space, "bolt_hit_ground"
## on a planet - data/effects.json), in its colour, sprayed back the way it came.
func _impact(at: Vector3) -> void:
	if cosmos == null or cosmos.get("world") == null:
		return
	var col := tint if tint.a > 0.0 else (Color(0.4, 0.9, 1.0) if side == "player" else Color(1.0, 0.35, 0.2))
	var back := -velocity.normalized()
	var fx: Fx
	if space:
		fx = Fx.spawn("bolt_hit", cosmos.world, at, 2.5 if orb else (1.8 if big else 1.0), Fx.basis_up(back))
	else:
		var pl = cosmos.planet_below(at, 50.0) if cosmos.has_method("planet_below") else null
		var up: Vector3 = (at - pl.global_position).normalized() if pl else back
		fx = Fx.spawn("bolt_hit_ground", cosmos.world, at, 1.0, Fx.basis_up((up + back).normalized()))
	if fx:
		fx.set_tint(col.lerp(Color.WHITE, 0.3))


## The segment a -> b this frame: true if it hit something (and dealt it).
func step(a: Vector3, b: Vector3) -> bool:
	if cosmos == null:
		return false
	var targets: Array = []
	if side == "player":
		if space:
			targets.append_array(cosmos.npc_ships)
			for m in cosmos.monsters:   # (along their bodies)
				if is_instance_valid(m) and not m.dead and m.bolt_hit(a, (b - a).normalized(), a.distance_to(b)):
					m.hurt(damage, a)
					return true
			if cosmos.law and cosmos.law.player_bolt(a, b, damage):   # (a station's parts: a crime, or war)
				return true
		else:
			targets.append_array(cosmos.creatures)
			targets.append_array(cosmos.npcs)
	elif side == "station":   # (a station's guns: at invaders and raiders)
		for x in cosmos.npc_ships:
			if is_instance_valid(x) and x.kind in ["invader", "pirate"]:
				targets.append(x)
	elif side == "invader":   # (at the station it besieges: the point it aimed at)
		return cosmos.law == null or cosmos.law.invader_bolt(self, a, b)
	elif space:
		targets.append(cosmos.ship)
	elif cosmos.walker:
		targets.append(cosmos.walker)
	var seg := b - a
	var L := seg.length()
	var dir := seg / maxf(L, 0.0001)
	for t in targets:
		if not is_instance_valid(t) or t.get("dead"):
			continue
		var r: float = t.get("reach") if t.get("reach") != null else 0.6
		if orb and t is CosmosShip:
			r = 12.0   # (the orbs: your hitbox smaller than your hull - hard to dodge, but dodgeable)
		var centre: Vector3 = t.global_position if space else t.global_position + (t.up() if t.has_method("up") else Vector3.UP) * maxf(r * 0.8, 0.9)
		var tc := clampf((centre - a).dot(dir), 0.0, L)
		if (a + dir * tc).distance_to(centre) < r + 0.25 + slack:
			if side == "player" and space and cosmos.law:
				cosmos.law.player_hit(t)
			var calm: bool = side == "station" and not t.get("hostile")
			t.hurt(damage, a)
			if calm and is_instance_valid(t):
				t.hostile = false   # (a station's fire turns no one on you)
			return true
	# What's been built (yours): the piece it strikes worn (CosmosBuilds) - anyone's bolts.
	if cosmos.get("builds") and cosmos.builds.bolt_hit(a, dir, L, damage):
		return true
	# A dungeon's walls.
	for d in cosmos.dungeons_live():
		if d.cam_hit(a, dir, L) < L:
			return true
	# The ground.
	var pl: CosmosPlanet = cosmos.planet_below(b, 50.0)
	if pl:
		var local := b - pl.global_position
		if pl.shape.carved_near(local):   # (dug ground - a cave, a dungeon, a tunnel: its rock, not the face above)
			if pl.shape.density(local) < 0.0:
				return true
		elif local.length() < pl.radius + pl.shape.surface(local.normalized()):
			return true
	return false
