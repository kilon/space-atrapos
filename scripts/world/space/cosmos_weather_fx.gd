class_name CosmosWeatherFx
extends Node3D
## The weather round you (the 3D game): each world's weather (PlanetWeather -
## local, moving cells) fed to its clouds and its ground (CosmosPlanet.
## weather_tick), and where you are: rain, snow or ash falling round the camera
## (GPU particles, slanting in a storm's wind), a storm's lightning (a bolt
## from the cloud base, its flash, the thunder after it as far off as it
## struck), the rain's hiss and the wind; none of it falling indoors, under the
## ground, aboard, in a hangar or under the sea. `now`: the weather where you
## are (the HUD's readout: the weather, the temperature, the radioactivity).

const TICK_S := 0.25            # s between looks at the weather where you are
const WORLDS_S := 1.5           # s between the worlds' cells sent to their clouds and ground
const BOX := 26.0               # m round the camera: where it falls
const KINDS := ["rain", "snow", "ash", "splash"]

var cosmos: Node
var now := {}                   # the weather where you are (PlanetWeather.at), {} off a world
var planet: CosmosPlanet = null # the world it's from
var sheltered := false          # (indoors, under the ground, aboard, docked, under the sea)
var _t := 0.0
var _worlds_t := 0.0
var _parts := {}                # kind -> GPUParticles3D
var _bolt_t := 3.0              # s to the next strike (in a storm)
var _flash: OmniLight3D
var _flash_k := 0.0
var _bolt: MeshInstance3D
var _bolt_life := 0.0
var _thunder: Array = []        # [s to wait, volume]
var _rain_snd: AudioStreamPlayer
var _wind_snd: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "WeatherFx"
	_rng.randomize()


func _process(delta: float) -> void:
	if cosmos == null or cosmos.get("cam") == null:
		return
	var cam: Camera3D = cosmos.cam
	_worlds_t -= delta
	if _worlds_t <= 0.0:
		_worlds_t = WORLDS_S
		for p: CosmosPlanet in cosmos.planets:
			if is_instance_valid(p):
				p.weather_tick(Galaxy.time, p.to_local(cam.global_position))
	_t -= delta
	if _t <= 0.0:
		_t = TICK_S
		_look(cam)
	var precip := float(now.get("precip", 0.0)) if not sheltered else 0.0
	var falls := str(now.get("falls", ""))
	var storm := float(now.get("storm", 0.0))
	var w: Node3D = cosmos.get("walker")
	var wet_eye := _eye_under(cam)   # (the camera under water - looked at every frame: no drop or flake down there, not even the last ones)
	for k in KINDS:   # (what falls here: its particles on, round the camera; the others off; the rain's splashes round your feet)
		var on: bool = (k == falls or (k == "splash" and falls == "rain" and w != null and w.get("deck") == null)) and precip > 0.03
		var gp: GPUParticles3D = _parts.get(k)
		if on and gp == null:
			gp = make_particles(k)
			add_child(gp)
			_parts[k] = gp
		if gp == null:
			continue
		gp.emitting = on and not wet_eye
		gp.visible = not wet_eye
		if on and not wet_eye:
			_follow(gp, cam, k, precip, storm)
	_lightning(delta, cam, storm if not sheltered else 0.0)
	_sounds(delta, precip, storm, falls)


## The camera under water: the sea's (below its level on a world with a sea), or a lake's or river's, or the
## underwater scene's own say.
func _eye_under(cam: Camera3D) -> bool:
	var uw = cosmos.get("underwater")
	if uw and uw.get("under"):
		return true
	var pl: CosmosPlanet = planet
	if pl == null:
		return false
	var lp := pl.to_local(cam.global_position)
	if pl.shape.sea > 0 and lp.length() < pl.radius - 0.05:
		return true
	if pl.shape.has_method("water_level"):
		var wl = pl.shape.water_level(lp.normalized())
		if wl is float and lp.length() < pl.radius + float(wl) - 0.05:
			return true
	return false


## The weather where you are (a few times a second): its world, the place under you.
func _look(cam: Camera3D) -> void:
	planet = null
	now = {}
	var focus: Node3D = cosmos.focus() if cosmos.has_method("focus") else cam
	var pl: CosmosPlanet = cosmos.planet_below(focus.global_position, 6000.0)
	if pl == null or pl.weather == null:
		return
	planet = pl
	var local := pl.to_local(cam.global_position)   # (planet-local: its weather's cells turn with it)
	var u := local.normalized()
	now = pl.weather.at(u, Galaxy.time, pl.sun_local)
	now["alt"] = local.length() - pl.radius
	var w: Node3D = cosmos.get("walker")
	sheltered = cosmos.get("docked") == true or cosmos.get("dungeon") != null
	if w and is_instance_valid(w):
		if w.get("deck") != null or w.get("diving") or w.get("swimming") and float(now["alt"]) < 0.0:
			sheltered = true
		elif cosmos.has_method("_under_ground") and cosmos._under_ground():
			sheltered = true
		else:
			var t = cosmos.town_at(pl, w.global_position) if cosmos.has_method("town_at") else null
			if t and t.indoors(t.to_local(w.global_position)):
				sheltered = true
			elif cosmos.get("builds") and cosmos.builds.planet == pl and cosmos.builds.indoors(w.global_position):
				sheltered = true
	var uw = cosmos.get("underwater")
	if uw and uw.get("under"):
		sheltered = true
	if float(now["alt"]) > (pl.atmo_radius - pl.radius):
		sheltered = true   # (out of the air: nothing falls up here)


## The particles placed over the camera, square to the world's up; how much falls, the wind.
func _follow(gp: GPUParticles3D, cam: Camera3D, k: String, precip: float, storm: float) -> void:
	var u := (cam.global_position - planet.global_position).normalized()
	var f := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized()
	var at := cam.global_position + u * (16.0 if k == "rain" else 3.0)
	if k == "splash":   # (on the ground round your feet)
		var wk: Node3D = cosmos.walker
		var lw := planet.to_local(wk.global_position)
		at = planet.to_global(lw.normalized() * (planet.radius + wk.floor_at(lw) + 0.03))
		gp.global_transform = Transform3D(Basis(f, u, f.cross(u)), at)
		gp.amount_ratio = clampf(precip * (1.0 + storm), 0.05, 1.0)
		return
	gp.global_transform = Transform3D(Basis(f, u, f.cross(u)), at)
	gp.amount_ratio = clampf(precip * (1.0 + storm), 0.05, 1.0)
	var pm := gp.process_material as ParticleProcessMaterial
	var wind := Vector3(0.6, 0.0, 0.25) * storm * (3.0 if k == "rain" else 6.0)   # (in a storm, slanting; a blizzard driven)
	pm.gravity = -u * (22.0 if k == "rain" else 1.2) + gp.global_basis * wind


## A storm's lightning: now and then a bolt from the cloud base to the ground, its
## flash over everything, the thunder as late as it's far.
func _lightning(delta: float, cam: Camera3D, storm: float) -> void:
	if _flash_k > 0.0:
		_flash_k = maxf(0.0, _flash_k - delta * 6.0)
		_flash.light_energy = _flash_k * 14.0 * (0.6 + 0.4 * sin(_flash_k * 40.0))
		_flash.visible = _flash_k > 0.0
	if _bolt and _bolt.visible:
		_bolt_life -= delta
		_bolt.visible = _bolt_life > 0.0 and fmod(_bolt_life, 0.08) > 0.025
	for i in range(_thunder.size() - 1, -1, -1):
		_thunder[i][0] -= delta
		if _thunder[i][0] <= 0.0:
			if not _headless():
				Sfx.play("weather/thunder" if not Sfx.takes("weather/thunder").is_empty() else "skill/thunder", float(_thunder[i][1]), 0.12)
			_thunder.remove_at(i)
	if storm < 0.3 or planet == null:
		return
	_bolt_t -= delta * storm
	if _bolt_t > 0.0:
		return
	_bolt_t = _rng.randf_range(3.0, 11.0)
	var u := (cam.global_position - planet.global_position).normalized()
	var side := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized().rotated(u, _rng.randf() * TAU)
	var dist := _rng.randf_range(150.0, 1400.0)
	var d := (u * planet.radius + side * dist).normalized()
	var ground := planet.global_position + d * (planet.radius + maxf(planet.shape.height(planet.dir_local(d)), 0.0))
	var cloud := planet.global_position + d * (planet.radius + planet.shape.top() * 0.85 + 25.0)
	_strike(cloud, ground, cam)
	_thunder.append([dist / 340.0, clampf(-4.0 - dist / 160.0, -16.0, -2.0)])


func _strike(top: Vector3, bottom: Vector3, cam: Camera3D) -> void:
	if _flash == null:
		_flash = OmniLight3D.new()
		_flash.light_color = Color(0.8, 0.85, 1.0)
		_flash.omni_range = 4000.0
		_flash.omni_attenuation = 0.5
		_flash.shadow_enabled = false
		add_child(_flash)
	_flash.global_position = top.lerp(bottom, 0.3)
	_flash_k = 1.0
	_flash.visible = true
	if _bolt == null:
		_bolt = MeshInstance3D.new()
		_bolt.material_override = bolt_mat()
		_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_bolt)
	_bolt.mesh = bolt_mesh(top, bottom, cam.global_position, _rng)
	_bolt.global_transform = Transform3D.IDENTITY
	_bolt.visible = true
	_bolt_life = 0.32


## The rain's hiss, the wind (its loops, up and down with the weather).
func _sounds(delta: float, precip: float, storm: float, falls: String) -> void:
	if _headless():
		return
	var want_rain := -60.0 if falls != "rain" or precip < 0.03 else lerpf(-26.0, -8.0, precip)
	var want_wind := -60.0 if planet == null or sheltered else lerpf(-34.0, -6.0, maxf(storm, precip * (0.6 if falls == "snow" else 0.3)))
	_rain_snd = _loop(_rain_snd, "weather/rain", want_rain, delta)
	_wind_snd = _loop(_wind_snd, "weather/wind", want_wind, delta)


func _loop(p: AudioStreamPlayer, key: String, want: float, delta: float) -> AudioStreamPlayer:
	if p == null:
		if want <= -55.0:
			return null
		var takes: Array = Sfx.takes(key)
		if takes.is_empty():
			return null
		var st: AudioStream = takes[0]
		if st is AudioStreamOggVorbis:
			st = st.duplicate()
			st.loop = true
		p = AudioStreamPlayer.new()
		p.stream = st
		p.bus = Sfx.BUS
		p.volume_db = -50.0
		add_child(p)
		p.play()
	p.volume_db = move_toward(p.volume_db, want, delta * 20.0)
	if p.volume_db <= -55.0 and want <= -55.0:
		p.queue_free()
		return null
	return p


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


# --- The looks (made once: CosmosWarm draws them at the title) ---------------------------

static var _mats := {}


## The particles of `kind` ("rain", "snow", "ash"): a box of them over the camera.
static func make_particles(kind: String) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.name = kind.capitalize()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 3.0
	var q: Mesh = QuadMesh.new()
	match kind:
		"rain":
			gp.amount = 11000
			gp.lifetime = 1.0
			pm.emission_box_extents = Vector3(BOX, 1.0, BOX)
			pm.initial_velocity_min = 14.0
			pm.initial_velocity_max = 18.0
			pm.gravity = Vector3(0, -22, 0)
			pm.particle_flag_align_y = true   # (its Y along its fall: a streak the way it falls)
			q = rain_mesh()
		"snow":
			gp.amount = 22000
			gp.lifetime = 9.0
			gp.preprocess = 9.0   # (the air full of it at once, not a front coming down)
			pm.emission_box_extents = Vector3(BOX * 0.55, 7.0, BOX * 0.55)   # (all round you, not just overhead: slow flakes don't fall far - and near: the fog has the rest)
			pm.initial_velocity_min = 0.8
			pm.initial_velocity_max = 1.6
			pm.gravity = Vector3(0, -1.2, 0)
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 1.2
			pm.turbulence_noise_scale = 4.0
			pm.turbulence_influence_min = 0.05
			pm.turbulence_influence_max = 0.15
			pm.scale_min = 0.35   # (flakes small and large, tumbling as they drift)
			pm.scale_max = 1.6
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.angular_velocity_min = -90.0
			pm.angular_velocity_max = 90.0
			(q as QuadMesh).size = Vector2(0.14, 0.14)
		"splash":   # (a drop's splash on the ground: a flick of spray up and out, gone in a blink)
			gp.amount = 1600
			gp.lifetime = 0.22
			pm.emission_box_extents = Vector3(16.0, 0.02, 16.0)
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 55.0
			pm.initial_velocity_min = 0.6
			pm.initial_velocity_max = 1.6
			pm.gravity = Vector3(0, -9.8, 0)
			pm.scale_min = 0.4
			pm.scale_max = 1.2
			var sc := CurveTexture.new()
			var cv := Curve.new()
			cv.add_point(Vector2(0, 0.3))
			cv.add_point(Vector2(1, 1.0))
			sc.curve = cv
			pm.scale_curve = sc
			var ramp := GradientTexture1D.new()
			var g := Gradient.new()
			g.set_color(0, Color(1, 1, 1, 0.8))
			g.set_color(1, Color(1, 1, 1, 0.0))
			ramp.gradient = g
			pm.color_ramp = ramp
			q = QuadMesh.new()
			(q as QuadMesh).size = Vector2(0.028, 0.028)
		_:   # (ash: grey flakes drifting down, embers among them)
			gp.amount = 4000
			gp.lifetime = 9.0
			gp.preprocess = 9.0
			pm.emission_box_extents = Vector3(BOX, 9.0, BOX)
			pm.initial_velocity_min = 0.4
			pm.initial_velocity_max = 1.0
			pm.gravity = Vector3(0, -0.8, 0)
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 0.8
			pm.turbulence_noise_scale = 3.0
			pm.scale_min = 0.5
			pm.scale_max = 1.6
			(q as QuadMesh).size = Vector2(0.08, 0.08)
	if q is PrimitiveMesh:
		(q as PrimitiveMesh).material = particle_mat(kind)
	else:
		(q as ArrayMesh).surface_set_material(0, particle_mat(kind))
	gp.process_material = pm
	gp.draw_pass_1 = q
	gp.local_coords = false
	gp.visibility_aabb = AABB(Vector3(-BOX - 10, -40, -BOX - 10), Vector3(BOX * 2 + 20, 60, BOX * 2 + 20))
	if kind == "rain":
		gp.preprocess = 1.0
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.emitting = false
	return gp


static func particle_mat(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	m.disable_fog = true   # (within metres of you: not lost in the veil they make - a blizzard's flakes white against its whiteout)
	match kind:
		"rain":
			m.albedo_color = Color(0.82, 0.86, 0.93, 0.28)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED   # (two crossed strips: seen from every side)
			m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA   # (a drop right by your eye: gone, not a white pole across the view)
			m.distance_fade_min_distance = 0.8
			m.distance_fade_max_distance = 4.0
		"snow":
			m.albedo_color = Color(0.97, 0.98, 1.0, 0.9)
			m.albedo_texture = _dot()
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		"splash":
			m.albedo_color = Color(0.85, 0.9, 0.97, 0.4)
			m.albedo_texture = _dot()
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_:
			m.albedo_color = Color(0.32, 0.3, 0.28, 0.85)
			m.albedo_texture = _dot()
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mats[kind] = m
	return m


static var _rain_mesh: ArrayMesh


## A raindrop's streak: two thin strips crossed along Y (0.9 m), no billboard - turned the way it falls (align_y).
static func rain_mesh() -> ArrayMesh:
	if _rain_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var w := 0.008
		var h := 0.5
		for ax in [Vector3(w, 0, 0), Vector3(0, 0, w)]:
			st.add_vertex(-ax + Vector3(0, -h, 0))
			st.add_vertex(ax + Vector3(0, -h, 0))
			st.add_vertex(ax + Vector3(0, h, 0))
			st.add_vertex(-ax + Vector3(0, -h, 0))
			st.add_vertex(ax + Vector3(0, h, 0))
			st.add_vertex(-ax + Vector3(0, h, 0))
		_rain_mesh = st.commit()
	return _rain_mesh


static var _dot_tex: Texture2D


## A soft round flake.
static func _dot() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 32
		t.height = 32
		_dot_tex = t
	return _dot_tex


static var _bolt_mat: StandardMaterial3D


static func bolt_mat() -> StandardMaterial3D:
	if _bolt_mat == null:
		_bolt_mat = StandardMaterial3D.new()
		_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bolt_mat.albedo_color = Color(0.85, 0.9, 1.0)
		_bolt_mat.emission_enabled = true
		_bolt_mat.emission = Color(0.7, 0.8, 1.0)
		_bolt_mat.emission_energy_multiplier = 6.0
		_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _bolt_mat


## A bolt from `top` to `bottom` (global): a jagged ribbon turned to the eye, a branch or two off it.
static func bolt_mesh(top: Vector3, bottom: Vector3, eye: Vector3, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bolt_line(st, top, bottom, eye, rng, 18, 3.5, 0.32)
	for b in rng.randi_range(1, 3):
		var a := top.lerp(bottom, rng.randf_range(0.2, 0.6))
		var off := (bottom - top).length() * 0.35
		var end := a + (bottom - top).normalized() * off + Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() * off * 0.6
		_bolt_line(st, a, end, eye, rng, 8, 1.6, 0.4)
	return st.commit()


static func _bolt_line(st: SurfaceTool, a: Vector3, b: Vector3, eye: Vector3, rng: RandomNumberGenerator, n: int, w: float, jag: float) -> void:
	var pts: Array = [a]
	var seg := (b - a) / n
	var L := seg.length()
	for i in range(1, n):
		pts.append(a + seg * i + Vector3(rng.randfn(), rng.randfn(), rng.randfn()) * L * jag)
	pts.append(b)
	for i in n:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var side := (p1 - p0).cross(eye - p0).normalized() * w * (1.0 - 0.5 * float(i) / n)
		st.add_vertex(p0 - side)
		st.add_vertex(p0 + side)
		st.add_vertex(p1 + side)
		st.add_vertex(p0 - side)
		st.add_vertex(p1 + side)
		st.add_vertex(p1 - side)
