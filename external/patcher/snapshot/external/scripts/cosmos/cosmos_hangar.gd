class_name CosmosHangar
extends Node3D
## A station's hangar in the 3D game (stage 4) - where your ship sets down
## when you dock: a great hall (built when you dock, freed when you leave)
## with a landing pad, the bay's mouth open to space behind a shimmering
## field, light panels overhead, cargo stacked about, cranes, the crew going
## about their work (automatons), and terminals along the back wall - the
## market, outfitting, missions, repairs (Stage 5 opens them). You walk its
## deck on foot (CosmosWalker's deck mode: floor at y = 0 in its own space,
## walls at BOUNDS).

const BOUNDS := Vector3(80.0, 34.0, 60.0)    # half sizes (x, height, z): a ~50 m ship on its pad, room round it
const PAD := Vector3(0, 0, 0)
## [label, the Station Menu's tab] (StationMenu.TABS: REPAIR, MARKET, OUTFITTING, SHIPYARD, DESIGNER, SELL, REPUTATION, MAIN QUESTS, MISSIONS)
const TERMINALS := [["Repair", 0], ["Market", 1], ["Outfitting", 2], ["Shipyard", 3], ["Designer", 4], ["Reputation", 6], ["Missions", 8]]
const CREW := 5

var station: CosmosStation
var terminals: Array = []       # [label, id, local position]
var _crew: Array = []           # [node, anim, goal]
var _rng := RandomNumberGenerator.new()


func setup(st: CosmosStation) -> void:
	station = st
	add_to_group("cam_solid")   # (the camera stops short of its parts)
	set_meta("cam_reach", 90.0)
	name = "Hangar"
	_rng.seed = hash(str(st.record.get("id", "")))
	var accent: Color = Galaxy.empire_color(str(st.record.get("empire", "")))
	var floor_m := CosmosStation._mat(Color(0.28, 0.29, 0.31), 0.4, 0.6)
	var wall := CosmosStation._mat(Color(0.5, 0.52, 0.55), 0.5, 0.5)
	var dark := CosmosStation._mat(Color(0.16, 0.17, 0.19), 0.6, 0.5)
	var lamp := CosmosStation._mat(Color(1, 0.95, 0.85), 0.0, 0.5, Color(1.0, 0.95, 0.85) * 4.0)
	var paint := CosmosStation._mat(accent.darkened(0.2), 0.3, 0.5)
	var glow := CosmosStation._mat(accent, 0.0, 0.5, accent * 3.0)
	var B := BOUNDS
	_box(Vector3(B.x * 2, 1, B.z * 2), Vector3(0, -0.5, 0), floor_m)
	# (the shell casts no shadows: the "sun" in here is the ceiling's lights)
	for b in [_box(Vector3(B.x * 2, 1, B.z * 2), Vector3(0, B.y + 0.5, 0), dark),
			_box(Vector3(1, B.y, B.z * 2), Vector3(-B.x - 0.5, B.y * 0.5, 0), wall),
			_box(Vector3(1, B.y, B.z * 2), Vector3(B.x + 0.5, B.y * 0.5, 0), wall),
			_box(Vector3(B.x * 2, B.y, 1), Vector3(0, B.y * 0.5, B.z + 0.5), wall)]:
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The bay's mouth (-z): a frame, the field across it.
	_box(Vector3(B.x * 2, 4, 1.5), Vector3(0, B.y - 2, -B.z), paint).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(Vector3(3, B.y, 1.5), Vector3(-B.x + 1.5, B.y * 0.5, -B.z), paint)
	_box(Vector3(3, B.y, 1.5), Vector3(B.x - 1.5, B.y * 0.5, -B.z), paint)
	var field := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(B.x * 2 - 6, B.y - 4)
	field.mesh = q
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://shaders/cosmos/gate.gdshader")
	fm.set_shader_parameter("tint", accent.lerp(Color(0.5, 0.8, 1.0), 0.5) * 0.35)
	fm.set_shader_parameter("noise_tex", Cosmos.noise_ready())
	field.material_override = fm
	field.position = Vector3(0, (B.y - 4) * 0.5, -B.z)
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(field)
	# The pad: rings of light.
	_box(Vector3(70, 0.2, 70), PAD + Vector3(0, 0.05, 0), dark)
	for r in [32.0, 33.0]:
		var t := TorusMesh.new()
		t.inner_radius = r - 0.15
		t.outer_radius = r + 0.15
		t.rings = 64
		t.ring_segments = 4
		var ring := MeshInstance3D.new()
		ring.mesh = t
		ring.material_override = glow
		ring.position = PAD + Vector3(0, 0.2, 0)
		add_child(ring)
	# Light panels overhead, stripes on the walls.
	for i in 4:
		for j in 3:
			_box(Vector3(18, 0.3, 4), Vector3(-54 + i * 36, B.y - 0.2, -36 + j * 36), lamp).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1.0, 1.0]:
		_box(Vector3(0.3, 0.6, B.z * 1.8), Vector3(side * (B.x - 0.1), 6, 0), glow)
	# Cargo stacks and a crane.
	for k in 14:
		var s := _rng.randf_range(1.6, 3.2)
		var at := Vector3(_rng.randf_range(-B.x + 4, B.x - 4), 0, _rng.randf_range(-B.z + 8, B.z - 4))
		if at.distance_to(PAD) < 40.0 or at.z > B.z - 10:
			continue
		for h in _rng.randi_range(1, 3):
			_box(Vector3(s, s, s * 1.4), at + Vector3(0, s * (h + 0.5) - s * 0.5 + s * 0.5 * 0.0, 0), paint if (k + h) % 3 == 0 else dark).rotation.y = _rng.randf() * 0.4
	_box(Vector3(1.2, B.y - 2, 1.2), Vector3(-B.x + 8, (B.y - 2) * 0.5, B.z - 8), dark)
	_box(Vector3(24, 1.2, 1.2), Vector3(-B.x + 18, B.y - 3, B.z - 8), dark)
	# Terminals along the back wall.
	for i in TERMINALS.size():
		var x := lerpf(-B.x + 10, B.x - 10, float(i) / (TERMINALS.size() - 1))
		var at := Vector3(x, 0, B.z - 1.8)
		_box(Vector3(2.2, 1.2, 0.9), at + Vector3(0, 0.6, 0), dark)
		var scr := _box(Vector3(2.0, 1.3, 0.12), at + Vector3(0, 1.9, -0.1), glow)
		scr.rotation.x = -0.25
		var l := Label3D.new()
		l.text = TERMINALS[i][0]
		l.font_size = 72
		l.pixel_size = 0.01
		l.position = at + Vector3(0, 3.3, 0)
		l.modulate = accent.lerp(Color.WHITE, 0.5)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
		terminals.append([TERMINALS[i][0], TERMINALS[i][1], at + Vector3(0, 0, -1.2)])
	# The crew.
	if Stage3D.has_model("player"):
		for i in CREW:
			var m: Node3D = Stage3D._scene("player").instantiate()
			CosmosModels.apply(m, "player")
			var holder := Node3D.new()
			holder.add_child(m)
			m.rotation.y = PI
			add_child(holder)
			holder.position = Vector3(_rng.randf_range(-B.x + 6, B.x - 6), 0, _rng.randf_range(0, B.z - 6))
			var anim: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
			if anim and anim.has_animation("walk"):
				anim.get_animation("walk").loop_mode = Animation.LOOP_LINEAR
				anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
				anim.play("idle")
			_crew.append([holder, anim, holder.position, _rng.randf_range(1.0, 4.0)])


func _process(delta: float) -> void:
	for c in _crew:
		var n: Node3D = c[0]
		var anim: AnimationPlayer = c[1]
		c[3] -= delta
		if c[3] <= 0.0:
			c[3] = _rng.randf_range(3.0, 8.0)
			c[2] = Vector3(_rng.randf_range(-BOUNDS.x + 6, BOUNDS.x - 6), 0, _rng.randf_range(-BOUNDS.z + 10, BOUNDS.z - 6))
			if (c[2] as Vector3).distance_to(PAD) < 36.0:
				c[2] = Vector3(signf((c[2] as Vector3).x + 0.01) * 50.0, 0, (c[2] as Vector3).z)
		var to: Vector3 = c[2] - n.position
		to.y = 0.0
		if to.length() > 0.5:
			n.position += to.normalized() * minf(1.6 * delta, to.length())
			n.rotation.y = atan2(-to.x, -to.z)
			if anim and anim.current_animation != "walk":
				anim.play("walk", 0.2)
		elif anim and anim.current_animation != "idle":
			anim.play("idle", 0.2)


func _box(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = CosmosStation._box(size)
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	return mi


## The terminal within reach of hangar-local `p`, or [].
func terminal_near(p: Vector3) -> Array:
	for t in terminals:
		if (t[2] as Vector3).distance_to(Vector3(p.x, 0, p.z)) < 2.6:
			return t
	return []


# --- The walker's deck (as CosmosShipInterior's) ---------------------------------

func floor_y(_l: Vector3) -> float:
	return 0.0


func ceiling_y(_l: Vector3) -> float:
	return BOUNDS.y


func confine(l: Vector3, m: float) -> Vector3:
	var c := inside(l, m)
	return Vector3(c.x, l.y, c.z)


## Keeps hangar-local `p` inside the walls (a margin `m` in).
static func inside(p: Vector3, m: float) -> Vector3:
	return Vector3(clampf(p.x, -BOUNDS.x + m, BOUNDS.x - m), clampf(p.y, 0.0, BOUNDS.y - m), clampf(p.z, -BOUNDS.z + m, BOUNDS.z - m))
