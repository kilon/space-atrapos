class_name SurfaceProps
extends RefCounted
## Things on a planet surface, all drawn procedurally for the isometric view.
## Each node's origin is at its "feet" so a y-sorted parent layers them
## correctly. Clickable objects have `title`, `click_radius`, `height` and
## interact(surface).

## Side view of your ship standing on its landing legs (used on planets).
const MINOAN_RED := Color(0.72, 0.18, 0.12)
const STONE := Color(0.8, 0.72, 0.58)
const GOLD := Color(1.0, 0.82, 0.38)


## (The baked disc stretched to the ellipse: batched, unlike draw_circle -
## dozens of shadows a frame on a planet.)
static func shadow(ci: CanvasItem, w: float, h: float, a := 0.3, origin := Vector2.ZERO) -> void:
	ci.draw_texture_rect(ExhaustTrail.disc(), Rect2(origin - Vector2(w, h), Vector2(w, h) * 2.0), false, Color(0, 0, 0, a))


## Base for clickable surface objects.
## A clear line of fire for `who` (its `surface`, or its shooter's) from
## ground point a to b (PlanetSurface.shot_clear; true off a surface).
static func clear_shot(who: Node, a: Vector2, b: Vector2) -> bool:
	if not is_instance_valid(who):
		return true
	var s: Node = who.get("surface")
	if s == null or not s.has_method("shot_clear"):
		return true
	return s.shot_clear(a, b)


class Thing extends Node2D:
	var title := ""
	var click_radius := 40.0
	var height := 40.0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_ENTER_TREE:
			add_to_group("surface_lift")   # (drawn lifted by the ground's elevation: PlanetSurface._apply_lifts)

	func click_center() -> Vector2:
		return global_position + Vector2(0, -height * 0.5)

	func interact(_surface: Node) -> void:
		pass


# --- The player on foot ----------------------------------------------------------

## You on foot: an armoured android with a rifle (SheetPuppet "player": the
## sheets external/images/player_on_foot_idle.png and _aim.png, 8 views each,
## cut to art/player/). Relaxed while walking or standing, facing the way you
## walk; the aiming pose only while you fire at an enemy (fire_at): it turns
## to the target, shoulders the rifle, fires laser bolts with recoil, and
## lowers it a moment after the last shot.
class Pilot extends Node2D:
	const HEIGHT := 128.0
	# Your weapon and how you stand up to things: from your loadout (Gear) and
	# the planet's environment - apply_gear().
	var reach := 700.0                # how far your weapon reaches
	var every := 0.22                 # s between shots
	var damage := 14.0
	var damage_type := "energy"
	var bolt_color := Color(1.0, 0.55, 0.2)
	var resists := {}                 # damage type -> share taken off (0..Gear.RESIST_CAP)
	var condition: Variant = null     # your parts' damage (the player's "condition": Parts)
	var hurt_taken := 0.0             # extra share of damage taken (a damaged frame)
	var overcharge_mult := 1.0        # how long an energy cell lasts (x)
	var accuracy := Accuracy.BASE_FOOT   # chance to hit (Accuracy: gear, upgrades, damaged optics)
	var evasion := 0.0                # how hard you are to hit
	var crit_chance := 0.0            # added to Upgrades.CRIT_BASE
	var crit_mult := 0.0
	const AIM_HOLD := 1.2             # s the rifle stays up after a shot

	var target := Vector2.ZERO
	## Height above the ground (px): on an upper floor, or climbing the stairs.
	## The position stays on the ground plane; only the drawing is lifted.
	var lift := 0.0
	var path := PackedVector2Array()   # route waypoints (from the surface's pathfinder)
	var moving := false
	var speed := SPEED                 # (the planet's environment may slow it: ice 0.8)
	var facing := 1.0                  # (left / right: kept for callers; the view follows the walk)
	var heading := Vector2(0, 1)       # the way it faces (screen space)
	var puppet: SheetPuppet
	var sprite: Sprite2D               # the picture shown (the puppet's)
	var view := ""
	var _phase := 0.0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_ENTER_TREE:
			add_to_group("surface_lift")
	var _walk := 0.0
	var _aiming := 0.0                 # > 0: the rifle is up (seconds left)
	var _cd := 0.0
	var _aim_at: Node2D
	var _last_pos := Vector2.ZERO
	## The enemy you're holding the trigger on (the surface sets it while the
	## fire button is held; null: not firing).
	var trigger: Node2D
	## Health on foot: pirates' bolts wear it down; it comes back once you're
	## out of the fight for a while; at 0 you're knocked out (the surface).
	const BASE_HP := 100.0
	var max_hp := BASE_HP
	const REGEN := 6.0                # per second, after CALM s without a hit
	const SPEED := 190.0              # px/s walking
	var regen_mult := 1.0             # the planet's environment (Planets.environment): volcanic 0.5
	const CALM := 4.0
	var hp := BASE_HP
	## The automaton's shield: it takes a hit before your health does, and
	## comes back quickly once you're out of the fight (SHIELD_CALM s).
	const BASE_SHIELD := 40.0
	const SHIELD_REGEN := 12.0        # per second
	const SHIELD_CALM := 3.0
	var max_shield := BASE_SHIELD
	var shield := BASE_SHIELD
	var surface: Node
	var _hurt := 0.0
	var _since_hit := 99.0
	## Stamina (Stamina): runs down as you go, faster in a fight; food and
	## energy drinks bring it back. Empty: slower, and no healing by itself.
	var stamina := Stamina.MAX

	## In a fight: hit lately, firing, or throwing blows.
	func fighting() -> bool:
		return _since_hit < CALM or trigger != null or _aiming > 0.0 or _fought < CALM

	# --- Skills (Skills; PlanetSurface.use_skill) ---
	## How it fights when you attack: "rifle", or a martial style (Skills).
	var style := "rifle"
	## Performing a move (a blow, a spell, a leap): s left - it stands (or flies) through it.
	var busy := 0.0
	## Off the ground (a leap, a flying kick): shots and blows miss.
	var airborne := false
	var hop := 0.0                     # extra height of the leap's arc (px)
	## Braced (Aspis Guard): s left, and the share of damage shrugged off.
	var guard_left := 0.0
	var guard_soak := 0.0
	## The Aegis Dome: s left, what it can still soak, what it could.
	var dome_left := 0.0
	var dome_hp := 0.0
	var dome_max := 1.0
	var dome: Node2D
	var _fought := 99.0                # s since the last blow / spell

	## A blow or a spell thrown: it's in a fight (the stance, the stamina).
	func fought() -> void:
		_fought = 0.0

	## Plays a move's clip (classic sheets: none) for `time` s; True if a clip plays.
	func perform(clip: String, time: float, speed := 1.0, hold := false) -> bool:
		busy = time
		moving = false
		path = PackedVector2Array()
		trigger = null
		_aiming = 0.0
		fought()
		return puppet.play(clip, speed, hold) if puppet else false

	## Hit hand to hand (a pirate's fist, a beast up close while you're in a
	## stance): as surface_hit, and it flinches if it isn't in the middle of a move.
	func struck(d: float, dtype := "kinetic") -> void:
		var was := hp
		surface_hit(d, dtype)
		if hp > 0.0 and hp < was and busy <= 0.0 and puppet and puppet.clip_mode:
			puppet.play("hit")
			busy = 0.2

	func tired() -> bool:
		return stamina <= 0.0

	## How fast it walks now (tired: slower).
	func walk_speed() -> float:
		return speed * (Stamina.TIRED_SPEED if tired() else 1.0)

	## Hurt: `d` damage of type `dtype` (Gear.DAMAGE_TYPES), less your resistance to it.
	func surface_hit(d: float, dtype := "kinetic") -> void:
		if hp <= 0.0 or airborne:
			return
		if dome_left > 0.0 and dome_hp > 0.0:      # (the Aegis Dome takes it)
			var took := minf(dome_hp, d)
			dome_hp -= took
			d -= took
			if dome and is_instance_valid(dome):
				dome.flash()
			if dome_hp <= 0.0:
				dome_left = 0.0
			if d <= 0.0:
				return
		if guard_left > 0.0:
			d *= 1.0 - guard_soak
		d *= 1.0 - float(resists.get(dtype, 0.0))
		d *= maxf(0.1, 1.0 + hurt_taken)   # (a damaged chassis frame: Parts)
		# The shield first: what it soaks never reaches you (nor your parts).
		var soak := minf(shield, d)
		shield -= soak
		d -= soak
		_since_hit = 0.0
		if d <= 0.0:
			_hurt = maxf(_hurt, 0.35)
			if surface and surface.has_method("close_menus_on_hit"):
				surface.close_menus_on_hit()   # (an attack all the same)
			return
		hp = maxf(0.0, hp - d)
		if hp > 0.0 and condition != null:
			var f := Parts.hit(condition, "automaton", d, max_hp, dtype)
			if not f.is_empty():
				GameLog.post(Parts.hit_text("automaton", f), "danger")
			var more := Parts.by_health(condition, "automaton", hp / maxf(1.0, max_hp), dtype)   # (the worse, the more)
			for m in more:
				GameLog.post(Parts.hit_text("automaton", m), "danger")
			if (not f.is_empty() or not more.is_empty()) and surface and surface.has_method("refresh_gear"):
				surface.refresh_gear()
		_hurt = 1.0
		_since_hit = 0.0
		if surface and surface.has_method("close_menus_on_hit"):
			surface.close_menus_on_hit()
		if hp <= 0.0 and surface and surface.has_method("knocked_out"):
			surface.knocked_out()

	func _ready() -> void:
		puppet = SheetPuppet.new()
		puppet.height = HEIGHT
		puppet.glow_color = Color(1.0, 0.55, 0.2)
		add_child(puppet)
		puppet.setup("player")
		sprite = puppet._sprite
		face(heading)
		_last_pos = position
		# (electrical faults crackling off it the worse it's hurt: FaultSparks)
		var fs := FaultSparks.attach(self, 34.0, func(): return 1.0 - hp / maxf(1.0, max_hp))
		fs.position = Vector2(0, -HEIGHT * 0.5)

	## Faces a screen direction (8 views).
	func face(v: Vector2) -> void:
		if v.length_squared() < 0.0001:
			return
		heading = v
		if puppet:
			puppet.set_facing(v)
			view = puppet._view

	## Seconds between shots: half while an energy cell overcharges the weapon.
	func fire_every() -> float:
		var over: float = surface.overcharge_left() if surface and surface.has_method("overcharge_left") else 0.0
		return every * (0.5 if over > 0.0 else 1.0)

	## Your stats from the loadout (Gear) and the planet's environment
	## (Planets.environment: its heat slows your healing, ice your walking -
	## heat and cold resistance take that much off the penalty).
	func apply_gear(player: Dictionary, env := {}) -> void:
		var lo := Gear.loadout(player)
		var fx := Gear.loadout_effects(lo)
		if not player.get("condition") is Dictionary:
			player["condition"] = {}
		condition = player["condition"]
		var dmg := Parts.effects(condition, "automaton")   # (damaged parts: Parts)
		for k in dmg:
			fx[k] = float(fx.get(k, 0.0)) + float(dmg[k])
		var ups := Upgrades.effects(player.get("upgrades"), condition, "automaton")   # (its components' upgrades)
		for k in ups:
			fx[k] = float(fx.get(k, 0.0)) + float(ups[k])
		hurt_taken = float(fx.get("hurt_taken_mult", 0.0))
		crit_chance = float(fx.get("crit_chance", 0.0))
		crit_mult = float(fx.get("crit_mult", 0.0))
		var w := Gear.weapon_stats(str(lo.get("weapon", Gear.DEFAULT_LOADOUT["weapon"])))
		damage = w["damage"] * (1.0 + float(fx.get("damage_mult", 0.0)))
		every = w["interval"] * maxf(0.25, 1.0 + float(fx.get("fire_rate_mult", 0.0)))
		reach = w["range"] * (1.0 + float(fx.get("range_mult", 0.0)))
		damage_type = w["type"]
		bolt_color = w["color"]
		resists = {}
		for t in Gear.DAMAGE_TYPES:
			resists[t] = clampf(float(fx.get("resist_" + t, 0.0)), 0.0, Gear.RESIST_CAP)
		var was := max_hp
		max_hp = maxf(20.0, BASE_HP + float(fx.get("max_hp", 0.0)))
		hp = clampf(hp + maxf(0.0, max_hp - was), 0.0, max_hp)
		var was_s := max_shield
		max_shield = maxf(0.0, BASE_SHIELD + float(fx.get("max_shield", 0.0)))
		shield = clampf(shield + maxf(0.0, max_shield - was_s), 0.0, max_shield)
		overcharge_mult = 1.0 + float(fx.get("overcharge_mult", 0.0))
		accuracy = clampf(Accuracy.BASE_FOOT + float(fx.get("accuracy", 0.0)), 0.2, 0.99)
		evasion = clampf(float(fx.get("evasion", 0.0)), 0.0, 0.6)
		var env_regen := float(env.get("regen", 1.0))
		var env_speed := float(env.get("speed", 1.0))
		env_regen = 1.0 - (1.0 - env_regen) * (1.0 - resists["heat"])
		env_speed = 1.0 - (1.0 - env_speed) * (1.0 - resists["cold"])
		regen_mult = env_regen * (1.0 + float(fx.get("regen_mult", 0.0)))
		speed = SPEED * env_speed * (1.0 + float(fx.get("speed_mult", 0.0)))

	## True while the rifle is up (firing, or just fired).
	func aiming() -> bool:
		return _aiming > 0.0

	## Fires at an enemy: turns to it, raises the rifle and shoots (one bolt
	## per call, rate-limited). False if it's out of reach or gone.
	func fire_at(foe: Node2D) -> bool:
		if not is_instance_valid(foe) or foe.get("dead") == true or position.distance_to(foe.position) > reach:
			return false   # (gone, fallen, or out of reach)
		if not SurfaceProps.clear_shot(self, position, foe.position):
			return false   # (a wall or rock in the way)
		_aim_at = foe
		_aiming = AIM_HOLD
		face(foe.position - position)
		puppet.raise_amt = 1.0
		puppet._process(0.0)   # (the aiming view now, so the muzzle is right)
		if _cd > 0.0:
			return true
		_cd = fire_every()
		puppet.release = 1.0
		puppet.cooling = 1.0
		var tip := puppet.muzzle() + puppet.position
		var bolt := LaserBolt.new()
		bolt.position = position + tip
		bolt.target = foe
		bolt.shooter = self
		bolt.speed = LaserBolt.SPEED
		var cr := Upgrades.crit(damage, crit_chance, crit_mult)   # (a weak spot now and then)
		bolt.damage = cr[0]
		bolt.crit = cr[1]
		bolt.color = bolt_color
		bolt.dtype = damage_type
		get_parent().add_child(bolt)
		var dir := (foe.position + Vector2(0, -40) - bolt.position).normalized()
		Glow.spawn(get_parent(), "fx_rifle_muzzle_small", bolt.position + dir * 6.0, 40.0, 0.12, dir.angle())
		return true

	func _process(delta: float) -> void:
		_cd = maxf(0.0, _cd - delta)
		_since_hit += delta
		_fought += delta
		busy = maxf(0.0, busy - delta)
		guard_left = maxf(0.0, guard_left - delta)
		if dome_left > 0.0:
			dome_left -= delta
			if dome and is_instance_valid(dome):
				dome.left = clampf(minf(dome_hp / maxf(1.0, dome_max), dome_left / 2.0), 0.0, 1.0)
		if dome_left <= 0.0 and dome != null:
			if is_instance_valid(dome):
				dome.queue_free()
			dome = null
		# (no healing while a part is damaged: Parts.regen_frozen)
		if hp > 0.0:
			stamina = maxf(0.0, stamina - Stamina.DRAIN * (Stamina.COMBAT if fighting() else 1.0) * delta)
		if _since_hit > CALM and hp < max_hp and not tired() and not (condition is Dictionary and Parts.regen_frozen(condition, "automaton")):
			hp = minf(max_hp, hp + REGEN * regen_mult * delta)
		if _since_hit > SHIELD_CALM and shield < max_shield:
			shield = minf(max_shield, shield + SHIELD_REGEN * delta)
		_hurt = move_toward(_hurt, 0.0, delta * 3.0)
		if puppet:
			puppet.modulate = Color.WHITE.lerp(Color(1.0, 0.3, 0.25), _hurt * 0.7)
		if trigger != null and busy <= 0.0 and not (is_instance_valid(trigger) and fire_at(trigger)):
			trigger = null   # (gone, or out of reach)
		var moved := position - _last_pos
		_last_pos = position
		if busy > 0.0:
			pass   # (a move: it faces the way it was thrown)
		elif _aiming > 0.0:
			_aiming -= delta
			if is_instance_valid(_aim_at):
				face(_aim_at.position - position)   # (keeps the target in its sights)
		elif moved.length() > 0.01:
			face(moved)
		# (the rifle in hand, or bare hands in a stance; walking or running by its speed)
		puppet.armed = style == "rifle"
		puppet.stance = "guard" if fighting() else "idle"
		puppet.gait = "run" if walk_speed() > 125.0 else "walk"
		if moved.length() > 0.01 and busy <= 0.0:
			_phase += moved.length() / puppet.stride_px() * TAU
		_walk = move_toward(_walk, 1.0 if moving and moved.length() > 0.01 and busy <= 0.0 else 0.0, delta * 6.0)
		puppet.raise_amt = 1.0 if _aiming > 0.0 else 0.0
		puppet.cooling = maxf(0.0, puppet.cooling - delta * 1.5)
		puppet.walk = _walk
		puppet.phase = _phase
		puppet.position = Vector2(0, -lift - hop)
		sprite = puppet._sprite
		queue_redraw()

	func _draw() -> void:
		draw_set_transform_matrix(Transform2D(0.0, Vector2(1.0, 0.4), 0.0, Vector2(0, -lift)))
		draw_circle(Vector2.ZERO, 22, Color(0, 0, 0, 0.3))
		draw_set_transform_matrix(Transform2D.IDENTITY)


# --- Your landed ship -------------------------------------------------------------

class Lander extends Thing:
	var _t := 0.0
	var ship_class := "player"
	var look := {}

	## Your own ship's sprite (with its paint job) laid on the pad in the
	## isometric view: turned along the grid and flattened onto the ground,
	## hovering a little above it over its shadow.
	func _ready() -> void:
		title = "Your ship  -  click to take off"
		click_radius = 120.0
		height = 120.0
		var art: Node = Engine.get_main_loop().root.get_node_or_null("ProcArt")
		if art == null:
			return
		var tex: Texture2D = art.sprite("ship_player") if ship_class in ["", "player"] else art.ship_texture(ship_class)
		if tex == null:
			return
		var ground := Node2D.new()
		ground.scale = Vector2(1.0, 0.56)
		ground.position = Vector2(0, -16)
		add_child(ground)
		var s := Sprite2D.new()
		s.texture = tex
		s.rotation = deg_to_rad(-55.0)
		s.scale = Vector2.ONE * (230.0 / maxf(tex.get_width(), tex.get_height()))
		s.material = ShipParts.material(look)
		ground.add_child(s)

	func _process(delta: float) -> void:
		_t += delta
		if UI.redraw_due(self, 30.0):   # (its blinking lights)
			queue_redraw()

	func _draw() -> void:
		# Landing pad: a flat diamond with blinking edge lights.
		var pad := PackedVector2Array([Vector2(0, -62), Vector2(135, 0), Vector2(0, 62), Vector2(-135, 0)])
		draw_colored_polygon(pad, Color(0.3, 0.32, 0.36))
		draw_polyline(pad + PackedVector2Array([pad[0]]), Color(0.9, 0.75, 0.2), 3.0, true)
		draw_line(Vector2(-60, 0), Vector2(60, 0), Color(0.9, 0.75, 0.2, 0.6), 2.0)
		draw_line(Vector2(0, -28), Vector2(0, 28), Color(0.9, 0.75, 0.2, 0.6), 2.0)
		for k in 4:
			var on := fmod(_t * 1.5 + k * 0.25, 1.0) < 0.5
			draw_circle(pad[k], 4.0, Color(0.4, 1.0, 0.6) if on else Color(0.2, 0.4, 0.25))
		# The ship's shadow on the pad.
		var sh := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24.0
			sh.append(Vector2(cos(a) * 92.0, sin(a) * 34.0).rotated(-0.45) + Vector2(0, 6))
		draw_colored_polygon(sh, Color(0, 0, 0, 0.28))

	func interact(surface: Node) -> void:
		surface.board_ship()   # (unload your pack, or take off)


class Building extends Thing:
	var style := "dome"
	var wall := Color.WHITE
	var light := Color.CYAN
	var description := ""
	var _t := 0.0

	func _ready() -> void:
		click_radius = 60.0
		height = 110.0 if style == "tower" else 70.0
		_t = randf() * 5.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		SurfaceProps.shadow(self, 52, 22, 0.25)
		var blink := fmod(_t, 2.0) < 1.0
		if style == "tower":
			draw_rect(Rect2(-18, -110, 36, 110), wall.darkened(0.1))
			draw_rect(Rect2(-18, -110, 12, 110), wall.darkened(0.3))
			draw_circle(Vector2(0, -110), 18.0, wall)
			for k in 3:
				draw_rect(Rect2(-5, -95 + k * 28, 10, 12), light)
			draw_line(Vector2(0, -128), Vector2(0, -150), wall.darkened(0.4), 2.0)
			draw_circle(Vector2(0, -150), 4.0, light if blink else light.darkened(0.6))
		else:
			# Dome: lit from the upper left, with a glowing door and window.
			draw_set_transform(Vector2(0, -6), 0.0, Vector2(1.0, 0.8))
			draw_circle(Vector2(0, -26), 46.0, wall.darkened(0.25))
			draw_circle(Vector2(-6, -32), 38.0, wall)
			draw_set_transform(Vector2.ZERO)
			draw_rect(Rect2(-10, -26, 20, 26), wall.darkened(0.6))
			draw_rect(Rect2(-7, -23, 14, 23), Color(light, 0.8))
			draw_circle(Vector2(24, -44), 6.0, Color(light, 0.9 if blink else 0.5))
			draw_line(Vector2(-12, -64), Vector2(-20, -84), wall.darkened(0.4), 2.0)
			draw_circle(Vector2(-20, -84), 3.0, light)

	func interact(surface: Node) -> void:
		GameLog.post(description, "info")
		surface.show_prompt(description)


# --- Minoan citizens -------------------------------------------------------------------

## The Minoan citizens: drawn from 8-view sprite sheets (SheetPuppet).
##   gunner       a triceratops guard with a laser rifle (MinoanGunner)
##   android      a ceramic-and-bronze android with a laser rifle (MinoanAndroid)
##   android_bow  ... with a laser bow (MinoanAndroidArcher)
##   android_axe  ... with a labrys, fighting hand to hand (MinoanAndroidAxe)
## They stroll around their home, chat when clicked, and shoot anything
## hostile (group "surface_hostiles") that comes in range.
const CITIZENS := ["gunner", "android", "android_bow", "android_axe"]


## A story character who gives you quests, standing in one place: drawn from
## an 8-view sprite sheet (SheetPuppet), turning to face you when you come
## near, a QuestBulb above his head while he has a quest for you (`offering`).
## Clicking him: the surface's talk_to_quest_giver (the conversation, with his
## portrait in the dialogue box). Not part of the fighting (nobody targets him).
## Kilon Alios (art/kilon/, from external/images/kilon_alios_sheet.png) stands
## by the landing pad on Amnissos and gives you the main quest.
class QuestGiver extends Thing:
	const HEIGHT := 132.0            # on screen, px (his long coat and hood)
	const NOTICE := 420.0            # turns to you within this distance (px)
	var npc_name := "Kilon Alios"
	var role := "Wanderer"
	var rig := "kilon"
	var surface: Node
	var puppet: SheetPuppet
	var bulb: QuestBulb
	var offering := true:
		set(v):
			offering = v
			if bulb:
				bulb.lit = v

	func _ready() -> void:
		title = "%s (%s)  -  click to talk" % [npc_name, role]
		click_radius = 46.0
		height = HEIGHT * 0.8
		puppet = SheetPuppet.new()
		puppet.height = HEIGHT
		add_child(puppet)
		puppet.setup(rig)
		puppet.set_facing(Vector2(0.3, 1))
		bulb = QuestBulb.new()
		bulb.position = Vector2(0, -HEIGHT - 30)
		bulb.radius = 12.0
		add_child(bulb)
		bulb.lit = offering

	func _process(_delta: float) -> void:
		var pilot: Node2D = surface.get("pilot") if surface else null
		if pilot and position.distance_to(pilot.position) < NOTICE:
			puppet.set_facing(pilot.position - position)

	func _draw() -> void:
		SurfaceProps.shadow(self, 24, 9)

	func interact(surface_: Node) -> void:
		if surface_.has_method("talk_to_quest_giver"):
			surface_.talk_to_quest_giver(self)


## The other empires' people (tools/empire_citizens.py draws their rigs):
## on a world the empire holds (MinoanTiles.culture), every citizen is one
## of them - its rig, its role, its names.
const CULTURE_CITIZENS := {
	"sparta": {"rig": "spartan", "role": "Spartan hoplite",
		"names": ["Brasidas", "Lysandros", "Agis", "Kleomenes", "Archidamos", "Dienekes", "Pausanias", "Gylippos",
			"Agesilaos", "Demaratos", "Eurybiadas", "Chilon", "Gorgo", "Kyniska", "Lampito", "Chilonis", "Agiatis", "Arete"]},
	"athens": {"rig": "athenian", "role": "Athenian citizen",
		"names": ["Kallias", "Nikias", "Alkibiades", "Aristeides", "Kimon", "Xanthippos", "Lysias", "Isokrates", "Phaidros",
			"Kritias", "Aspasia", "Diotima", "Hipparete", "Agariste", "Myrrhine", "Theodote", "Elpinike", "Philonike"]},
	"mycenae": {"rig": "mycenaean", "role": "Mycenaean warrior",
		"names": ["Agapenor", "Atreides", "Diomedes", "Sthenelos", "Eurypylos", "Talthybios", "Pelagon", "Ekhelawon",
			"Alxoitas", "Aithalos", "Klytaimnestra", "Elektra", "Iphianassa", "Laodike", "Eriboia", "Aerope"]},
	"ionia": {"rig": "ionian", "role": "Ionian scholar",
		"names": ["Hekataios", "Anaximenes", "Thales", "Bias", "Hippodamos", "Xenophanes", "Melissos", "Pherekydes",
			"Leukippos", "Mimnermos", "Theano", "Aspasia", "Sappho", "Arete", "Damo", "Myia"]},
	"cyclades": {"rig": "cycladic", "role": "Islander",
		"names": ["Anios", "Kynthios", "Akamas", "Phanes", "Euthymos", "Nikandre", "Rhoio", "Oino", "Spermo", "Elais",
			"Delia", "Asteria", "Kreousa", "Melia", "Naxia", "Parthenia"]},
}


## A citizen of the given kind (CITIZENS, "pirate"; anything else: by variant).
static func citizen(kind: String, variant := 0) -> MinoanNpc:
	if kind == "pirate":
		var p := SurfacePirate.new()
		p.variant = variant
		return p
	if CULTURE_CITIZENS.has(MinoanTiles.culture):
		var cc: Dictionary = CULTURE_CITIZENS[MinoanTiles.culture]
		var g := MinoanGunner.new()
		g.variant = variant
		g.rig_name = cc["rig"]
		g.role = cc["role"]
		g.culture_names = cc["names"]
		return g
	if not kind in CITIZENS:
		kind = CITIZENS[posmod(variant, CITIZENS.size())]
	var c: MinoanNpc
	match kind:
		"android": c = MinoanAndroid.new()
		"android_bow": c = MinoanAndroidArcher.new()
		"android_axe": c = MinoanAndroidAxe.new()
		_: c = MinoanGunner.new()
	c.variant = variant
	return c


## What the citizens (and the pirates) share: a sprite-sheet puppet, strolling about their
## home along the surface's paths, a speech bubble, a chat when clicked.
class MinoanNpc extends Thing:
	const HEIGHT := 122.0            # on screen, px (taller than the pilot)
	const STRIDE := 64.0             # px walked per full walk cycle (two steps)
	const WALK_SPEED := 58.0
	const NAMES := ["Minos", "Glaukos", "Deukalion", "Katreus", "Idomeneus", "Rhadamanthys", "Sarpedon", "Androgeos"]
	const FEMALE_NAMES := ["Ariadne", "Phaedra", "Pasiphae", "Europa", "Britomartis", "Akakallis", "Diktynna", "Krete"]

	var species := "gunner"
	var role := "Minoan citizen"
	var rig_name := "gunner"
	## Names for a culture's people (CULTURE_CITIZENS); [] - the Minoans'.
	var culture_names: Array = []
	var female := false
	var npc_name := ""
	var variant := 0
	var home := Vector2.ZERO
	var surface: Node
	var puppet: SheetPuppet
	var wander := 260.0              # how far from home they stroll
	var watch: Node2D                # a single foe to keep shooting at (the zoo's drone)
	var _phase := 0.0
	var _walk := 0.0
	var _path := PackedVector2Array()
	var _wait := 1.0
	var _st := 0.0
	var _bubble := ""
	var _bubble_t := 0.0
	var _bubble_node: Node2D
	## Health: laser bolts (pirates', yours) wear it down; at 0 they fall.
	var max_hp := 80.0
	var last_hit_by: Node2D          # whose shot or blow hit last (yours: a kill of yours - LostItems)
	var hp := -1.0
	var dead := false
	var _hurt := 0.0
	## Has a quest for you: a QuestBulb floats above their head.
	var quest_giver := false:
		set(v):
			quest_giver = v
			if is_inside_tree():
				_update_bulb()
	var _bulb: QuestBulb

	func _ready() -> void:
		if hp < 0.0:
			hp = max_hp
		if npc_name == "":
			var pool: Array = _names()
			npc_name = pool[(variant / CITIZENS.size()) % pool.size()]
		title = "%s (%s)  -  click to talk" % [npc_name, role]
		click_radius = 44.0
		height = HEIGHT * 0.8
		_wait = randf_range(0.3, 2.5)
		puppet = _new_puppet()
		add_child(puppet)
		puppet.setup(rig_name)
		puppet.stride = STRIDE
		puppet.set_facing(Vector2(1, 0.5))
		# Speech bubble on its own layer, above neighbouring citizens and walls.
		_bubble_node = Node2D.new()
		_bubble_node.z_index = 20
		_bubble_node.draw.connect(_draw_bubble)
		add_child(_bubble_node)
		_update_bulb()

	func _update_bulb() -> void:
		if quest_giver and _bulb == null:
			_bulb = QuestBulb.new()
			_bulb.position = Vector2(0, -HEIGHT - 34)
			add_child(_bulb)
		if _bulb:
			_bulb.lit = quest_giver and not dead

	## Where their names come from.
	func _names() -> Array:
		if not culture_names.is_empty():
			return culture_names
		return FEMALE_NAMES if female else NAMES

	## The figure: 8-view sprite sheets.
	func _new_puppet() -> SheetPuppet:
		return SheetPuppet.new()

	static func _texture(key: String) -> Texture2D:
		var tree := Engine.get_main_loop() as SceneTree
		var art: Node = tree.root.get_node_or_null("ProcArt") if tree else null
		return art.sprite(key) if art else null   # (drawn as they are: a placeholder till the picture is in - ProcArt.sprite)

	## The nearest hostile within `reach` (or the one they're told to watch).
	var _foe_cache: Node2D = null
	var _foe_searched_at := 0

	func _foe(reach: float) -> Node2D:
		if is_instance_valid(watch):
			return watch if position.distance_to(watch.position) < reach else null
		# (Looked for again every 0.15 s: the search tests a line of fire to each
		# hostile near - every frame for every guard in a fight was a lot.)
		var now := Time.get_ticks_msec()
		if now - _foe_searched_at < 150 and (_foe_cache == null or is_instance_valid(_foe_cache)):
			return _foe_cache if _foe_cache == null or (not _foe_cache.get("dead") and position.distance_to(_foe_cache.position) < reach) else null
		_foe_searched_at = now
		_foe_cache = _foe_search(reach)
		return _foe_cache

	func _foe_search(reach: float) -> Node2D:
		var best: Node2D = null
		var best_d := reach
		for h in get_tree().get_nodes_in_group("surface_hostiles"):
			var d: float = position.distance_to(h.position)
			if d < best_d and SurfaceProps.clear_shot(self, position, h.position):   # (not through walls)
				best = h
				best_d = d
		return best

	## Faces a target (left / right) and aims at it: the aim angle from chest height.
	func _aim_toward(at: Node2D) -> void:
		var d := at.position + Vector2(0, -30) - (position + Vector2(0, -HEIGHT * 0.62))
		puppet.set_facing(d)   # (8 views: straight at it)
		puppet.aim = atan2(d.y, absf(d.x))

	## One step of strolling: along the current path, or picking a new spot
	## near home after a pause. True while walking.
	func _stroll(delta: float) -> bool:
		if not _path.is_empty():
			var goal: Vector2 = _path[0]
			var d := position.distance_to(goal)
			if d < 4.0:
				_path.remove_at(0)
				return true
			var step := position.direction_to(goal) * minf(WALK_SPEED * delta, d)
			if surface and surface.walkable_at(position + step):
				position += step
				_phase += step.length() / puppet.stride_px() * TAU
				puppet.set_facing(step)
				return true
			_path = PackedVector2Array()
			return false
		_wait -= delta
		if _wait <= 0.0:
			_wait = randf_range(1.5, 5.0)
			_next_errand()
		return false

	## Where to go next: a spot near home.
	func _next_errand() -> void:
		var g := home + Vector2(randf_range(-wander, wander), randf_range(-wander, wander) * 0.5)
		if surface and surface.walkable_at(g):
			_path = surface.find_path(position, g)   # walks around walls, through doors

	func _go(s: String) -> void:
		set("_state", s)
		_st = 0.0

	## Hit by a bolt: a red flash, and down at 0 health.
	func surface_hit(d: float, _dtype := "") -> void:
		if dead:
			return
		hp -= d
		_hurt = 1.0
		if hp <= 0.0:
			_die()

	## Staggered by a blow (Skills): it can't act for `t` s - reeling (the
	## "hit" clip), or floored (down: it falls, lies there, gets up again).
	var _stun := 0.0
	var _down := false

	func stagger(t: float, down := false) -> void:
		if dead:
			return
		_stun = maxf(_stun, t)
		if puppet and puppet.clip_mode:
			if down:
				if not _down:
					puppet.play("ko", 1.7, true)
				_down = true
			elif not _down:
				puppet.play("hit")

	## True while it's staggered (call first in _process: nothing else happens).
	func _stunned(delta: float) -> bool:
		if _stun <= 0.0:
			return false
		_stun -= delta
		if _down and _stun <= 0.4:      # (up again: the fall, played backwards)
			_down = false
			puppet.play("ko", 1.8, false, true)
		_animate(delta, false)
		return true

	## Falls: out of the fight, fades away (the surface drops a pirate's loot).
	func _die() -> void:
		dead = true
		remove_from_group("surface_hostiles")
		set_process(false)
		if surface and surface.has_method("npc_died"):
			surface.npc_died(self)
		var tw := create_tween()
		if puppet and puppet.clip_mode and (_down or puppet.play("ko", 1.0, true)):
			# (it has a fall of its own: down it goes, and lies there a moment)
			if _down:
				puppet.play("ko", 4.0, true)
			puppet.modulate = Color.WHITE
			tw.tween_property(self, "modulate:a", 0.0, 0.9).set_delay(1.5)
		else:
			tw.tween_property(self, "rotation", 1.3 if randf() < 0.5 else -1.3, 0.35)
			tw.parallel().tween_property(self, "modulate:a", 0.0, 1.2).set_delay(0.4)
		tw.tween_callback(queue_free)

	func _animate(delta: float, moving: bool) -> void:
		_hurt = move_toward(_hurt, 0.0, delta * 3.0)
		puppet.modulate = Color.WHITE.lerp(Color(1.0, 0.35, 0.3), _hurt * 0.7)
		_walk = move_toward(_walk, 1.0 if moving else 0.0, delta * 5.0)
		puppet.walk = _walk
		puppet.phase = _phase
		_bubble_t = maxf(0.0, _bubble_t - delta)
		_bubble_node.queue_redraw()

	func say(line: Array) -> void:
		_bubble = line[0]
		_bubble_t = 4.0
		GameLog.post('%s: "%s"  (%s)' % [npc_name, line[0], line[1]], "mission")

	func _draw() -> void:
		SurfaceProps.shadow(self, 22, 8)

	func _draw_bubble() -> void:
		var c := _bubble_node
		if hp < max_hp and not dead:   # a health bar once hurt
			var w := 54.0
			var r := Rect2(-w / 2.0, -HEIGHT - 14, w, 6)
			c.draw_rect(r.grow(1), Color(0, 0, 0, 0.7))
			c.draw_rect(Rect2(r.position, Vector2(w * clampf(hp / max_hp, 0.0, 1.0), 6)), Color(1.0, 0.3, 0.25) if species == "pirate" else Color(0.4, 0.95, 0.5))
		if _bubble_t > 0.0:
			var font := ThemeDB.fallback_font
			var size := Settings.fs("world", 14)
			var w := font.get_string_size(_bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 20
			var box := Rect2(Vector2(-w / 2.0, -HEIGHT - 26 - size), Vector2(w, size + 14))
			c.draw_rect(box, Color(1, 1, 1, 0.92))
			c.draw_colored_polygon(PackedVector2Array([Vector2(-6, box.end.y), Vector2(6, box.end.y), Vector2(0, box.end.y + 8)]), Color(1, 1, 1, 0.92))
			c.draw_string(font, Vector2(box.position.x, box.position.y + size + 3), _bubble, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(0.1, 0.1, 0.15))

	func interact(surface_: Node) -> void:
		var line: Array = Planets.NPC_LINES.pick_random()
		say(line)
		# Face to face: the conversation window with their portrait.
		Scenarios.event("talked", {"planet": str(surface_.planet_id)})
		Comms.open(surface_, "citizen-%d" % variant, "minoa", role + " of " + str(surface_.pdata["name"]),
			"%s  (%s)" % [line[0], line[1]], [], species, npc_name)


## The Minoan guard: a triceratops android with a laser rifle, drawn from the
## sprite sheets external/images/minoan_npc_guard_idle.png (relaxed) and
## _aim.png (aiming), 8 views each (SheetPuppet). He patrols the
## streets with the rifle at the ready; when a hostile comes in range he
## shoulders it, aims and fires bursts of laser bolts (muzzle flash, recoil,
## the vents glowing as it cools), and lowers it once the threat is gone.
class MinoanGunner extends MinoanNpc:
	var reach := 650.0               # fires at hostiles this close (px)
	var burst := 3                   # shots per burst
	var every := 0.16                # s between shots in a burst
	var cool := 0.7                  # s between bursts
	var damage := 12.0
	var shot_sprite := "fx_rifle_bolt"

	var _state := "walk"              # walk / raise / fire / cool / lower
	var _raise := 0.0
	var _shots := 0
	var _aim_at: Node2D

	func _init() -> void:
		species = "gunner"
		rig_name = "gunner"
		role = "Minoan guard"
		max_hp = 130.0

	func _process(delta: float) -> void:
		_st += delta
		var moving := false
		var foe := _foe(reach)
		match _state:
			"walk":
				_raise = move_toward(_raise, 0.0, delta * 2.5)
				if foe:
					_aim_at = foe
					_path = PackedVector2Array()
					_go("raise")
				else:
					moving = _stroll(delta)
			"raise":   # shoulder the rifle toward the threat
				if is_instance_valid(_aim_at):
					_aim_toward(_aim_at)
				_raise = move_toward(_raise, 1.0, delta * 3.2)
				if _raise >= 1.0 and _st > 0.3:
					_shots = burst
					_go("fire")
			"fire":
				if not is_instance_valid(_aim_at) or position.distance_to(_aim_at.position) > reach * 1.1:
					_go("lower")
				else:
					_aim_toward(_aim_at)
					if _st >= every:
						_shoot()
						_shots -= 1
						_st = 0.0
						if _shots <= 0:
							_go("cool")
			"cool":   # vents glowing; a new burst if the threat remains
				puppet.cooling = clampf(1.0 - _st / cool, 0.0, 1.0)
				if is_instance_valid(_aim_at):
					_aim_toward(_aim_at)
				if _st > cool:
					var next := foe if foe else null
					if next:
						_aim_at = next
						_shots = burst
						_go("fire")
					else:
						_go("lower")
			"lower":
				_raise = move_toward(_raise, 0.0, delta * 2.0)
				if _raise <= 0.0:
					_wait = randf_range(1.0, 2.5)
					_go("walk")
		puppet.raise_amt = smoothstep(0.0, 1.0, _raise)
		_animate(delta, moving)

	## Where a bolt leaves the muzzle (local space).
	func _tip() -> Vector2:
		return puppet.muzzle()

	func _shoot() -> void:
		if not is_instance_valid(_aim_at) or not SurfaceProps.clear_shot(self, position, _aim_at.position):
			return   # (a wall or rock in the way: no shot)
		puppet.release = 1.0
		puppet.cooling = 1.0
		var tip := _tip()
		var bolt := LaserBolt.new()
		bolt.position = position + tip
		bolt.target = _aim_at
		bolt.shooter = self
		bolt.speed = LaserBolt.SPEED
		bolt.damage = damage
		bolt.texture = _texture(shot_sprite)
		_dress(bolt)
		get_parent().add_child(bolt)
		var dir := (_aim_at.position + Vector2(0, -40) - bolt.position).normalized()
		_flash(position + tip, dir)

	## The androids give their shots their own look.
	func _dress(_bolt: LaserBolt) -> void:
		pass

	## The flash where a shot leaves the weapon.
	func _flash(at: Vector2, dir: Vector2) -> void:
		Glow.spawn(get_parent(), "fx_rifle_muzzle_small", at + dir * 6.0, 40.0, 0.12, dir.angle())


## The Minoan androids: machines of cream ceramic and bronze built in a
## triceratops's image (a frill painted with red spirals, cyan eyes, a glowing
## core), in a red cape and kilt - drawn from 8-view sprite sheets cut by
## tools/android_sheets.py from external/images/minoan_android_<weapon>.png,
## their shots and slashes from minoan_android_fx.png (fx_android_*). Tougher
## than flesh; named for the automata of the Cretan myths (Talos and his kin).
## Three of them, by weapon:
##   android      a laser rifle - the guard's ways: bursts of cyan bolts
##   android_bow  a laser bow - one slow, hard-hitting arrow at a time, from further off
##   android_axe  a labrys - no shots: it closes in and cleaves (MinoanAndroidAxe)
class MinoanAndroid extends MinoanGunner:
	const ANDROID_NAMES := ["Talos", "Chryseos", "Argyreos", "Kelmis", "Akmon", "Damnameneus", "Kaminos", "Kedalion"]

	func _init() -> void:
		species = "android"
		rig_name = "android_rifle"
		role = "Minoan android"
		max_hp = 170.0
		wander = 200.0
		shot_sprite = "fx_android_bolt"

	func _names() -> Array:
		return ANDROID_NAMES

	func _dress(bolt: LaserBolt) -> void:
		bolt.length = 64.0
		bolt.impact = "fx_android_bolt_impact"
		bolt.impact_size = 60.0


## The android archer: draws its laser bow and looses one glowing arrow at a
## time - slower than the rifle, but further and harder.
class MinoanAndroidArcher extends MinoanAndroid:
	func _init() -> void:
		super()
		species = "android_bow"
		rig_name = "android_bow"
		role = "Minoan android archer"
		max_hp = 150.0
		reach = 780.0
		burst = 1
		cool = 1.1
		damage = 26.0
		shot_sprite = "fx_android_arrow"

	func _dress(bolt: LaserBolt) -> void:
		bolt.speed = 2200.0
		bolt.length = 78.0
		bolt.impact = "fx_android_arrow_impact"
		bolt.impact_size = 66.0

	func _flash(at: Vector2, _dir: Vector2) -> void:
		Glow.spawn(get_parent(), "fx_android_bow_flash", at, 52.0, 0.22)


## The android with the labrys, the Minoan double axe: it has no shots - it
## strides up to a hostile (faster than it strolls), winds the axe up over its
## shoulder (the raise1 pictures) and cleaves (the strike pictures, with their
## slash): a heavy blow within STRIKE_REACH, a cyan slash and a shockwave on
## the ground. Then it steps back into guard and goes again while the foe stands.
class MinoanAndroidAxe extends MinoanAndroid:
	const STRIKE_REACH := 78.0       # px: close enough to cleave
	const CHASE_SPEED := 96.0        # px/s
	const WIND_UP := 0.45            # s, the axe over the shoulder
	const RECOVER := 0.6             # s after the blow
	var _foe_at: Node2D
	var _repath := 0.0

	func _init() -> void:
		super()
		species = "android_axe"
		rig_name = "android_axe"
		role = "Minoan android guardian"
		max_hp = 220.0
		reach = 520.0
		damage = 34.0

	func _process(delta: float) -> void:
		_st += delta
		var moving := false
		match _state:
			"walk":
				_raise = move_toward(_raise, 0.0, delta * 3.0)
				var foe := _foe(reach)
				if foe:
					_foe_at = foe
					_path = PackedVector2Array()
					_go("chase")
				else:
					moving = _stroll(delta)
			"chase":   # stride up to it
				_raise = move_toward(_raise, 0.0, delta * 3.0)
				if not _alive(_foe_at) or position.distance_to(_foe_at.position) > reach * 1.4:
					_go("walk")
				elif position.distance_to(_foe_at.position) <= STRIKE_REACH:
					_aim_toward(_foe_at)
					_go("wind")
				else:
					moving = _close_in(delta)
			"wind":   # the axe up over the shoulder
				if _alive(_foe_at):
					_aim_toward(_foe_at)
				_raise = move_toward(_raise, 0.5, delta * 3.0)
				if _st >= WIND_UP:
					_raise = 1.0
					_cleave()
					_go("recover")
			"recover":
				if _st >= RECOVER * 0.4:
					_raise = move_toward(_raise, 0.0, delta * 3.0)
				if _st >= RECOVER:
					_go("chase" if _alive(_foe_at) else "walk")
		puppet.raise_amt = _raise
		_animate(delta, moving)

	func _alive(n: Variant) -> bool:   # (Variant: a freed foe mustn't fail the typed call)
		return is_instance_valid(n) and n.get("dead") != true

	## One step toward the foe: straight at it, or round walls along a path.
	func _close_in(delta: float) -> bool:
		var to := _foe_at.position
		var step := position.direction_to(to) * CHASE_SPEED * delta
		if surface == null or surface.walkable_at(position + step):
			position += step
			_phase += step.length() / puppet.stride_px() * TAU
			puppet.set_facing(step)
			return true
		_repath -= delta
		if _path.is_empty() or _repath <= 0.0:
			_repath = 0.5
			_path = surface.find_path(position, to) if surface.has_method("find_path") else PackedVector2Array()
		return _stroll(delta * CHASE_SPEED / WALK_SPEED) if not _path.is_empty() else false

	## The blow: it lands if the foe is still within reach.
	func _cleave() -> void:
		puppet.release = 1.0
		var dir := Vector2.RIGHT
		if is_instance_valid(_foe_at):
			dir = (_foe_at.position - position).normalized()
		var at := position + dir * 40.0 + Vector2(0, -36)
		Glow.spawn(get_parent(), "fx_android_slash", at, 96.0, 0.3, dir.angle())
		Glow.spawn(get_parent(), "fx_android_shockwave", position + dir * 46.0, 90.0, 0.4)
		if _alive(_foe_at) and position.distance_to(_foe_at.position) <= STRIKE_REACH * 1.3:
			if "last_hit_by" in _foe_at:
				_foe_at.last_hit_by = self
			if _foe_at.has_method("surface_hit"):
				_foe_at.surface_hit(damage)
			if _foe_at.has_method("attacked_by"):
				_foe_at.attacked_by(self)
			Glow.spawn(get_parent(), "fx_android_axe_sparks", _foe_at.position + Vector2(0, -40), 70.0, 0.3, randf() * TAU)


## A brief glowing effect (flash, impact burst): grows a little and fades, additive.
## A pirate raider: an evil android in a tattered coat with a rifle (4 attack
## frames, 8 views each in art/pirate/, cut from its reference sheets by tools/character_sheets.py -
## external/blender/pirate/: rifle down - the idle frame, walking - then raising it and
## firing: it raises the rifle through the frames, fires from the last, and
## lowers it again when there's no one left to shoot). Pirates
## roam in bands and shoot whoever comes in range - you and the citizens,
## never another pirate - in bursts of red bolts. They count as hostile
## (group "surface_hostiles"): guards fire back, and so can you
## (right-click / F). When one falls it drops loot (the surface's npc_died).
## Shot at, it fights back: it turns on whoever hit it - closing in first if
## they're out of its reach (a grudge of GRUDGE s, up to GRUDGE_RANGE away).
## Badly hurt (FLEE_HP of its health or less), it lowers its rifle and runs
## from the fight (FLEE_SPEED - slower than you), until it's FLEE_SAFE away.
class SurfacePirate extends MinoanNpc:
	const RANGE := 560.0
	const BURST := 3
	const EVERY := 0.2               # s between shots in a burst
	const COOL := 1.2                # s between bursts
	const DAMAGE := 6.0
	const PIRATE_NAMES := ["Rust-Jaw", "Kraken", "Black Vane", "Grimtide", "Scuttle", "Hookhand", "Bilge", "Red Cog",
		"Saltbones", "Deadlight", "Barnacle", "Ironbeard"]
	const TAUNTS := ["Your drachmas or your circuits!", "Nothing personal, it's plunder.", "This rock is ours now.",
		"Run, little pilot!", "Yo-ho... and a barrel of coolant!"]
	const RAISE_TIME := 0.45           # s to bring the rifle up (through the raise frames)
	const LOWER_TIME := 0.6
	const GRUDGE := 15.0               # s it goes after whoever shot it
	const GRUDGE_RANGE := 1600.0       # ... unless they get this far away
	const CHASE_SPEED := 85.0          # px/s, closing in on them
	const FLEE_HP := 0.3               # of max_hp: at or below it runs
	const FLEE_SPEED := 120.0          # px/s (you walk at 190: you can catch it)
	const FLEE_SAFE := 950.0           # px from the threat: far enough
	const FLEE_TIME := 9.0             # s at most, then it stops where it is
	const FLEE_LINES := ["Fall back! Fall back!", "Not worth my circuits!", "You'll pay for this... later!",
		"Retreat, retreat!"]
	var _state := "walk"              # walk / raise / fire / cool / lower / chase / flee
	var _avenge: Node2D                # who shot it (its grudge)
	var _grudge := 0.0                 # s left of it
	var _threat: Node2D                # what it runs from
	var _shots := 0
	var _raise := 0.0                  # 0 rifle down (idle frame) .. 1 aimed
	var _aim_at: Node2D
	var _look := 0.0                   # time to the next look around for targets
	# Hand to hand (its sprites' martial arts: clip mode only): this close it
	# slings the rifle and fights with fists and feet - a blow every BRAWL_EVERY
	# s or so, picked from BRAWL_MOVES [clip, damage]; every third pirate is a
	# brawler: it charges from BRAWLER_CHARGE px instead of shooting.
	const BRAWL_RANGE := 100.0
	const BRAWL_REACH := 72.0
	const BRAWL_SPEED := 100.0
	const BRAWLER_SPEED := 150.0
	const BRAWLER_CHARGE := 420.0
	const BRAWL_EVERY := 0.55
	const BLOCK_CHANCE := 0.22
	const BRAWL_MOVES := [["jab", 5.0], ["cross", 7.0], ["hook", 8.0], ["uppercut", 11.0], ["front", 9.0], ["round", 11.0],
		["side", 9.0], ["sweep", 8.0]]
	var brawler := false
	var _blow := {}                    # the blow being thrown: {t, hit, time, damage, done}
	var _next_blow := 0.3

	func _init() -> void:
		species = "pirate"
		rig_name = "pirate"
		role = "pirate raider"
		max_hp = 70.0
		wander = 520.0

	func _ready() -> void:
		npc_name = PIRATE_NAMES[posmod(variant, PIRATE_NAMES.size())]
		super()
		title = "%s (pirate)  -  right-click or F to fire" % npc_name
		add_to_group("surface_hostiles")
		add_to_group("surface_pirates")
		_look = randf() * 0.25
		brawler = variant % 3 == 0

	## Close enough to fight hand to hand (a brawler: to charge)?
	func _brawl_at(t: Node2D) -> bool:
		if not puppet.clip_mode or not is_instance_valid(t) or hurt_badly():
			return false
		var d := position.distance_to(t.position)
		return d < BRAWL_RANGE or (brawler and d < BRAWLER_CHARGE)

	## A blow of yours it sees coming, now and then: most of it is blocked.
	func try_block() -> bool:
		if _state != "brawl" or not _blow.is_empty() or _stun > 0.0 or randf() >= BLOCK_CHANCE:
			return false
		puppet.play("block", 1.0)
		_next_blow = maxf(_next_blow, 0.35)
		_st = 0.0
		return true

	func _throw_blow() -> void:
		var m: Array = BRAWL_MOVES[randi() % BRAWL_MOVES.size()]
		if not puppet.play(str(m[0])):
			return
		_aim_toward(_aim_at)
		_blow = {"t": 0.0, "hit": maxf(0.05, puppet.mark_time(str(m[0]), "hit")), "time": puppet.clip_time(str(m[0])),
			"damage": float(m[1]), "done": false}
		_sound("raise", -8.0)

	func _land_blow() -> void:
		var t := _aim_at
		if not is_instance_valid(t) or t.get("dead") == true or t.get("airborne") == true \
				or position.distance_to(t.position) > BRAWL_REACH * 1.35:
			return
		if "last_hit_by" in t:
			t.last_hit_by = self
		if t.has_method("struck"):
			t.struck(float(_blow["damage"]), "kinetic")
		elif t.has_method("surface_hit"):
			t.surface_hit(float(_blow["damage"]), "kinetic")
		if t.has_method("attacked_by"):
			t.attacked_by(self)
		SkillFx.impact(get_parent(), t.position + Vector2(0, -52), Color(1.0, 0.5, 0.35), 0.8)
		var sfx := get_node_or_null("/root/Sfx")
		if sfx:
			sfx.play_at("skill/punch", position, get_parent(), -4.0)

	func _new_puppet() -> SheetPuppet:
		var p := SheetPuppet.new()
		p.glow_color = Color(1.0, 0.35, 0.25)
		return p

	## The nearest living target in reach: you, or anyone who isn't a pirate -
	## whoever shot it first, while it holds a grudge.
	func _target() -> Node2D:
		if is_instance_valid(watch):   # (the Library: a drone to shoot at)
			return watch if position.distance_to(watch.position) < RANGE else null
		if _grudge > 0.0 and _alive(_avenge):
			return _avenge
		if surface == null:
			return null
		var best: Node2D = null
		var best_d := RANGE
		var you: Node2D = surface.get("pilot")
		if you and surface.has_method("pilot_targetable") and surface.pilot_targetable():
			var d := position.distance_to(you.position)
			if d < best_d and SurfaceProps.clear_shot(self, position, you.position):
				best = you
				best_d = d
		for n in surface.npcs:
			if n == self or not is_instance_valid(n) or n.dead or n.species == "pirate":
				continue
			var d: float = position.distance_to(n.position)
			if d < best_d and SurfaceProps.clear_shot(self, position, n.position):
				best = n
				best_d = d
		return best

	func _alive(t: Variant) -> bool:   # (Variant: a freed target mustn't fail the typed call)
		if not is_instance_valid(t) or position.distance_to(t.position) > RANGE * 1.15:
			return false
		if t.get("dead") == true:
			return false
		if surface and t == surface.get("pilot"):
			return surface.pilot_targetable()
		return true

	func hurt_badly() -> bool:
		return hp <= max_hp * FLEE_HP

	## Hit by someone (a bolt / arrow they fired): it fights back - or, badly
	## hurt, runs from them.
	func attacked_by(who: Node2D) -> void:
		if dead or not is_instance_valid(who) or who == self or who.get("species") == "pirate":
			return
		_avenge = who
		_grudge = GRUDGE
		if hurt_badly():
			_flee_from(who)
			return
		match _state:
			"walk", "lower", "chase":
				_path = PackedVector2Array()
				if _alive(who):
					_aim_at = who
					_go("raise")      # (from wherever the rifle is)
				else:
					_go("chase")
			"raise", "fire", "cool":
				if not (_aim_at and _alive(_aim_at) and _aim_at == who) and _alive(who):
					_aim_at = who     # (turns on whoever's shooting it)
			"brawl":
				if _alive(who) and (not _alive(_aim_at) or position.distance_to(who.position) < position.distance_to(_aim_at.position)):
					_aim_at = who

	func _flee_from(who: Node2D) -> void:
		_threat = who
		_path = PackedVector2Array()
		if _state != "flee":
			_go("flee")
			say([FLEE_LINES.pick_random(), "a pirate, fleeing"])
			_sound("flee")

	## One step in direction dir (or as near it as the ground allows); true if it moved.
	func _step(dir: Vector2, speed: float, delta: float) -> bool:
		if surface == null:
			return false
		for turn in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
			var step := dir.rotated(turn).normalized() * speed * delta
			if surface.walkable_at(position + step):
				position += step
				_phase += step.length() / puppet.stride_px() * TAU
				puppet.set_facing(step)
				return true
		return false

	func _process(delta: float) -> void:
		if _stunned(delta):
			_blow = {}
			return
		_st += delta
		var moving := false
		_look -= delta
		_grudge = maxf(0.0, _grudge - delta)
		if _state in ["raise", "fire", "cool"] and _alive(_aim_at) and _brawl_at(_aim_at):
			_go("brawl")
		puppet.armed = _state != "brawl"
		puppet.stance = "guard"
		puppet.gait = "walk"
		match _state:
			"brawl":   # hand to hand: closing in, throwing blows
				_raise = move_toward(_raise, 0.0, delta / 0.2)
				if not _blow.is_empty():
					_blow["t"] = float(_blow["t"]) + delta
					if not _blow["done"] and float(_blow["t"]) >= float(_blow["hit"]):
						_blow["done"] = true
						_land_blow()
					if float(_blow["t"]) >= float(_blow["time"]):
						_blow = {}
						_st = 0.0
						_next_blow = BRAWL_EVERY * randf_range(0.6, 1.5)
				elif not _alive(_aim_at):
					_look = 0.0
					_go("walk")
				elif hurt_badly():
					_flee_from(_aim_at)
				else:
					var d := position.distance_to(_aim_at.position)
					if d > (BRAWLER_CHARGE * 1.25 if brawler else BRAWL_RANGE * 1.7):
						_go("raise")       # (it got away: the rifle again)
					elif d > BRAWL_REACH * 0.8:
						moving = _step(position.direction_to(_aim_at.position), BRAWLER_SPEED if brawler else BRAWL_SPEED, delta)
					else:
						_aim_toward(_aim_at)
						if _st >= _next_blow:
							_throw_blow()
			"walk":
				if _look <= 0.0:
					_look = 0.25
					_aim_at = _target()
					if _aim_at and _alive(_aim_at) and hurt_badly():
						_flee_from(_aim_at)   # (hurt: it won't pick a fight)
				if _state == "flee":
					pass
				elif _aim_at and _alive(_aim_at) and _brawl_at(_aim_at):
					_path = PackedVector2Array()
					_go("brawl")
				elif _aim_at and _alive(_aim_at):
					_path = PackedVector2Array()
					_go("raise")
				elif _grudge > 0.0 and is_instance_valid(_avenge) and _avenge.get("dead") != true \
						and position.distance_to(_avenge.position) < GRUDGE_RANGE:
					_path = PackedVector2Array()
					_go("chase")
				else:
					moving = _stroll(delta)
			"chase":   # closing in on whoever shot it
				if _grudge <= 0.0 or not is_instance_valid(_avenge) or _avenge.get("dead") == true \
						or position.distance_to(_avenge.position) > GRUDGE_RANGE:
					_go("walk")
				elif position.distance_to(_avenge.position) < RANGE * 0.85 and _alive(_avenge):
					_aim_at = _avenge
					_go("raise")
				else:
					moving = _step(position.direction_to(_avenge.position), CHASE_SPEED, delta)
			"flee":    # running from the fight, rifle down
				_raise = move_toward(_raise, 0.0, delta / 0.3)
				var gone: bool = not is_instance_valid(_threat) or _threat.get("dead") == true
				if gone or position.distance_to(_threat.position) > FLEE_SAFE or _st > FLEE_TIME:
					home = position   # (it lies low here, not back where the fight was)
					_grudge = 0.0
					_wait = randf_range(2.0, 4.0)
					_look = 1.0
					_go("walk")
				else:
					moving = _step(_threat.position.direction_to(position), FLEE_SPEED, delta)
			"raise":   # the rifle comes up (frames 1 -> 4)
				if _aim_at and _alive(_aim_at):
					_aim_toward(_aim_at)
				_raise = move_toward(_raise, 1.0, delta / RAISE_TIME)
				if _raise >= 1.0:
					_shots = BURST
					_go("fire")
			"fire":
				if not _alive(_aim_at):
					_go("cool")
				else:
					_aim_toward(_aim_at)
					if _st >= EVERY:
						_shoot()
						_shots -= 1
						_st = 0.0
						if _shots <= 0:
							_go("cool")
			"cool":
				if _aim_at and _alive(_aim_at):
					_aim_toward(_aim_at)
				if _st > COOL:
					_aim_at = _target()
					if _aim_at and _alive(_aim_at):
						_shots = BURST   # still a target: fire again, rifle still up
						_go("fire")
					else:
						_go("lower")
			"lower":   # the rifle goes down (frames 4 -> 1)
				_raise = move_toward(_raise, 0.0, delta / LOWER_TIME)
				if _raise <= 0.0:
					_look = 0.0
					_go("walk")
		puppet.raise_amt = _raise
		_animate(delta, moving)

	func _shoot() -> void:
		if not is_instance_valid(_aim_at) or not SurfaceProps.clear_shot(self, position, _aim_at.position):
			return   # (a wall or rock in the way: no shot)
		puppet.release = 1.0
		puppet.cooling = 1.0
		var tip: Vector2 = puppet.muzzle()
		var bolt := LaserBolt.new()
		bolt.position = position + tip
		bolt.target = _aim_at
		bolt.shooter = self
		bolt.speed = LaserBolt.SPEED
		bolt.damage = DAMAGE
		bolt.color = Color(1.0, 0.25, 0.2)
		get_parent().add_child(bolt)
		var sfx := get_node_or_null("/root/Sfx")
		if sfx:
			sfx.play_at("pirate/shot", position + tip, get_parent())

	func interact(_surface: Node) -> void:
		say([TAUNTS.pick_random(), "a pirate's growl"])
		_sound("taunt")

	# --- Sounds (Sfx: sounds/pirate/, made by tools/sfx_pirate.py) ---------------

	var _step_k := 0                   # (which half of the walk cycle: a footstep each)
	var _hurt_sound := 0.0             # (no new grunt within 0.3 s of the last)

	func _sound(name: String, volume_db := 0.0) -> void:
		var sfx := get_node_or_null("/root/Sfx")
		if sfx and get_parent():
			sfx.play_at("pirate/" + name, position, get_parent(), volume_db)

	func _go(s: String) -> void:
		if s == "raise" and _state != "raise" and _raise < 0.5:
			_sound("raise", -2.0)
		elif s == "lower" and _state != "lower":
			_sound("lower", -3.0)
		super(s)

	func surface_hit(d: float, _dtype := "") -> void:
		if not dead and hp - d > 0.0 and _hurt_sound <= 0.0:
			_hurt_sound = 0.3
			_sound("hurt")
		super(d)

	func _die() -> void:
		if not dead:
			_sound("death")
		super()

	func _animate(delta: float, moving: bool) -> void:
		super(delta, moving)
		_hurt_sound = maxf(0.0, _hurt_sound - delta)
		var k := floori(_phase / PI)       # (a footstep every half cycle - each foot)
		if k != _step_k:
			_step_k = k
			if moving:
				_sound("step", -6.0)


## An eidolon (Skills: Eidola): a spectral fighter called up by the automaton -
## its own figure, pale and see-through - that goes for the nearest enemy with
## fists and feet (MOVES, `damage` a blow), keeps near you when there's none,
## and fades when its time (`life`) is up or it's beaten. Pirates shoot at it
## as at anyone (it's among the surface's npcs).
class Eidolon extends MinoanNpc:
	const SPEED := 210.0
	const REACH := 66.0
	const SEEK := 640.0
	const MOVES := ["jab", "cross", "hook", "front", "round", "side", "elbow", "knee"]
	var master: Node2D
	var life := 18.0
	var damage := 10.0
	var _enemy: Node2D
	var _blow := {}
	var _look := 0.0
	var _next := 0.2

	func _init() -> void:
		species = "eidolon"
		rig_name = "player"
		role = "eidolon"
		max_hp = 60.0

	func _ready() -> void:
		npc_name = "Eidolon"
		super()
		title = "An eidolon  -  yours"
		click_radius = 0.0
		puppet.armed = false
		puppet.stance = "guard"
		puppet.gait = "run"
		modulate = Color(0.5, 0.95, 1.0, 0.0)
		create_tween().tween_property(self, "modulate:a", 0.78, 0.5)

	func interact(_surface: Node) -> void:
		pass

	func _nearest_enemy() -> Node2D:
		var best: Node2D = null
		var best_d := SEEK
		var from: Vector2 = master.position if is_instance_valid(master) else position
		for h in get_tree().get_nodes_in_group("surface_hostiles"):
			if h.get("dead") == true:
				continue
			var d: float = from.distance_to(h.position) * 0.5 + position.distance_to(h.position) * 0.5
			if d < best_d:
				best = h
				best_d = d
		return best

	func _step_to(at: Vector2, delta: float) -> bool:
		var dir := position.direction_to(at)
		for turn in [0.0, 0.6, -0.6, 1.2, -1.2]:
			var step := dir.rotated(turn) * SPEED * delta
			if surface == null or surface.walkable_at(position + step):
				position += step
				_phase += step.length() / puppet.stride_px() * TAU
				puppet.set_facing(step)
				return true
		return false

	func _process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			vanish()
			return
		_st += delta
		_look -= delta
		if _look <= 0.0:
			_look = 0.3
			_enemy = _nearest_enemy()
		var moving := false
		if not _blow.is_empty():
			_blow["t"] = float(_blow["t"]) + delta
			if not _blow["done"] and float(_blow["t"]) >= float(_blow["hit"]):
				_blow["done"] = true
				var t := _enemy
				if is_instance_valid(t) and t.get("dead") != true and position.distance_to(t.position) < REACH * 1.4:
					if "last_hit_by" in t:
						t.last_hit_by = master
					elif "last_by" in t:
						t.last_by = master
					t.surface_hit(damage, "energy")
					if t.has_method("attacked_by"):
						t.attacked_by(self)
					if t.has_method("stagger"):
						t.stagger(0.3)
					SkillFx.impact(get_parent(), t.position + Vector2(0, -52), Color(0.5, 0.95, 1.0), 0.8)
			if float(_blow["t"]) >= float(_blow["time"]):
				_blow = {}
				_st = 0.0
				_next = randf_range(0.1, 0.4)
		elif is_instance_valid(_enemy) and _enemy.get("dead") != true:
			var d := position.distance_to(_enemy.position)
			if d > REACH * 0.85:
				moving = _step_to(_enemy.position, delta)
			else:
				puppet.set_facing(_enemy.position - position)
				if _st >= _next:
					var m: String = MOVES[randi() % MOVES.size()]
					if puppet.play(m, 1.15):
						_blow = {"t": 0.0, "hit": maxf(0.05, puppet.mark_time(m, "hit") / 1.15), "time": puppet.clip_time(m) / 1.15, "done": false}
					else:   # (the classic sheets: no clips - it just strikes)
						_blow = {"t": 0.0, "hit": 0.15, "time": 0.45, "done": false}
		elif is_instance_valid(master) and position.distance_to(master.position) > 120.0:
			moving = _step_to(master.position, delta)
		_animate(delta, moving)

	func vanish() -> void:
		if dead:
			return
		dead = true
		set_process(false)
		if surface:
			surface.npcs.erase(self)
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.6)
		tw.tween_callback(queue_free)

	func _die() -> void:
		vanish()


## What a fallen pirate leaves behind: a small glowing chest; walk over it
## to take what's inside (contents: [[item id or "credits", amount], ...]).
class LootDrop extends Thing:
	var contents: Array = []
	var label := "Pirate loot"
	var light := Color(1.0, 0.3, 0.2, 0.9)   # (a pirate's red light; a beast's: cyan)
	var _t := 0.0

	func _ready() -> void:
		title = label + "  -  walk over it to take it"
		click_radius = 36.0
		height = 30.0
		_t = randf() * 3.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		SurfaceProps.shadow(self, 18, 7, 0.35)
		var y := -8.0 - 3.0 * (0.5 + 0.5 * sin(_t * 3.0))
		var glow := 0.5 + 0.5 * sin(_t * 4.0)
		draw_circle(Vector2(0, y - 6), 26.0, Color(1.0, 0.7, 0.25, 0.12 + 0.1 * glow))
		draw_rect(Rect2(-14, y - 12, 28, 16), Color(0.42, 0.24, 0.12))
		draw_rect(Rect2(-14, y - 18, 28, 7), Color(0.55, 0.32, 0.16))
		draw_rect(Rect2(-14, y - 12, 28, 2), Color(0.85, 0.65, 0.25))
		draw_rect(Rect2(-3, y - 14, 6, 6), Color(1.0, 0.8, 0.3))
		draw_circle(Vector2(0, y - 22), 3.0 + glow, light)


class Glow extends Sprite2D:
	var life := 0.3
	var _age := 0.0
	var _k := 1.0

	static func spawn(parent: Node, key: String, at: Vector2, size: float, life_s: float, rot := 0.0) -> Glow:
		var tex := MinoanNpc._texture(key)
		if tex == null:
			return null
		var g := Glow.new()
		g.texture = tex
		g._k = size / maxf(tex.get_width(), tex.get_height())
		g.scale = Vector2.ONE * g._k
		g.position = at
		g.rotation = rot
		g.life = life_s
		g.z_index = 16
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		g.material = m
		parent.add_child(g)
		return g

	func _process(delta: float) -> void:
		_age += delta
		var f := _age / life
		scale = Vector2.ONE * _k * (0.8 + 0.5 * f)
		modulate.a = clampf(1.0 - f * f, 0.0, 1.0)
		if f >= 1.0:
			queue_free()


## A laser bolt fired by an armed citizen: flies at its target and hits it
## (calls surface_hit(damage) on it).
## A laser bolt: very fast, and homing - it steers to where its target is
## now every frame, so it can't be outrun or dodged (if the target falls
## first, it flies on and fades out).
class LaserBolt extends Node2D:
	const SPEED := 2600.0
	const GROUND := 50.0                # px down from the bolt to the ground under it
	var target: Node2D
	var shooter: Node2D                # who fired it (the target hears of it: attacked_by)
	var speed := SPEED
	var damage := 10.0
	var color := Color(0.35, 0.8, 1.0)
	var dtype := "energy"              # its damage type (Gear.DAMAGE_TYPES)
	var texture: Texture2D             # a glowing bolt sprite (else drawn lines)
	var length := 58.0                 # the sprite's length on screen (px)
	var impact := "fx_rifle_impact"    # the glow where it strikes
	var impact_size := 54.0
	var _dir := Vector2.RIGHT
	var _life := 1.5
	## Whether it lands (Accuracy): rolled as it's fired, from the shooter's
	## accuracy (its "accuracy", or ACC); a miss is aimed past the target and
	## flies on by - into the ground beyond, or a wall.
	var accuracy := -1.0
	const ACC := 0.75
	var missed := false
	var crit := false                  # a critical hit (Upgrades.crit): it says so when it lands

	func _notification(what: int) -> void:
		if what == NOTIFICATION_ENTER_TREE:
			add_to_group("surface_lift")

	func _ready() -> void:
		z_index = 15
		if is_instance_valid(target):
			var acc := accuracy
			if acc < 0.0:
				acc = float(shooter.get("accuracy")) if is_instance_valid(shooter) and shooter.get("accuracy") != null else ACC
			var aim := _aim_point()
			if acc < 1.0 and randf() >= _chance(acc):   # (1: a sure shot - tests, scripted fire)
				missed = true
				var side := (aim - position).orthogonal().normalized() * (1.0 if randf() < 0.5 else -1.0)
				aim += side * randf_range(38.0, 70.0)
				target = null   # (it flies on past)
				_life = 0.6
				var fx := get_parent()
				if fx:
					Effects.float_text(aim + Vector2(0, -40), "MISS", Color(0.8, 0.85, 0.95))
			_dir = (aim - position).normalized()
		rotation = _dir.angle()

	## The chance this shot lands: the shooter's accuracy less the target's
	## evasion, and a little less the further (Accuracy.chance's rules, on foot).
	func _chance(acc: float) -> float:
		var d := position.distance_to(target.position)
		var ev := float(target.get("evasion")) if target.get("evasion") != null else 0.0
		if target.get("moving") == true:
			ev += 0.06
		return clampf(acc * (1.0 - ev) - 0.12 * clampf(d / 700.0 - 0.5, 0.0, 1.0), Accuracy.MIN_HIT, Accuracy.MAX_HIT)

	func _process(delta: float) -> void:
		_life -= delta
		var step := speed * delta
		if is_instance_valid(target) and target.get("dead") != true:
			var aim := _aim_point() - position
			# Reaches it this frame (checked before moving: at this speed a bolt
			# would otherwise skip right past).
			if aim.length() <= step + 26.0 and target.get("airborne") == true:
				target = null      # (it leapt: the shot flies on under it)
				_life = minf(_life, 0.5)
				position += _dir * step
				return
			if aim.length() <= step + 26.0:
				position += aim
				if "last_hit_by" in target:
					target.last_hit_by = shooter
				if target.has_method("surface_hit"):
					target.surface_hit(damage, dtype)
				if crit:
					Effects.float_text(position + Vector2(0, -50), "CRITICAL", Color(1.0, 0.8, 0.3))
				if target.has_method("attacked_by") and is_instance_valid(shooter):
					target.attacked_by(shooter)
				if is_instance_valid(shooter) and shooter.get("species") == "pirate":   # (a pirate's bolt striking)
					var sfx := get_node_or_null("/root/Sfx")
					if sfx:
						sfx.play_at("pirate/bolt_hit", position, get_parent(), -2.0)
				if texture:
					Glow.spawn(get_parent(), impact, position, impact_size, 0.28, randf() * TAU)
				queue_free()
				return
			_dir = aim.normalized()   # (homing)
			rotation = _dir.angle()
		# A wall or rock across its path (on the ground, under it): it bursts there.
		var g := position + Vector2(0, GROUND)
		if not SurfaceProps.clear_shot(shooter, g, g + _dir * step):
			if texture:
				Glow.spawn(get_parent(), impact, position, impact_size, 0.28, randf() * TAU)
			queue_free()
			return
		position += _dir * step
		if _life <= 0.0:
			queue_free()

	## Where it strikes its target: chest height (a flying animal: up where it flies).
	func _aim_point() -> Vector2:
		var up = target.get("_alt")
		return target.position + Vector2(0, -40.0 - (float(up) if up != null else 0.0))

	func _draw() -> void:
		if texture:
			var k := length / texture.get_width()
			draw_set_transform(Vector2(-length * 0.38, 0), 0.0, Vector2(k, k))
			draw_texture(texture, -texture.get_size() / 2.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
		draw_line(Vector2(-26, 0), Vector2(6, 0), Color(color, 0.35), 9.0, true)
		draw_line(Vector2(-22, 0), Vector2(4, 0), color, 4.0, true)
		draw_line(Vector2(-18, 0), Vector2(3, 0), Color(1, 1, 1, 0.9), 1.5, true)


# --- Scenery ---------------------------------------------------------------------------

class Prop extends Node2D:
	var kind := "rock"
	var color := Color.GRAY
	var s := 1.0
	var variant := 0   # random seed for this prop's shape
	var _o := Vector2.ZERO   # drawing origin (PropBatch draws many props)

	func _draw() -> void:
		if preload("res://scripts/terrain_tiles.gd").is_piece(kind):   # a tile set's tree, shrub or rock (TerrainTiles)
			var tex: Texture2D = preload("res://scripts/terrain_tiles.gd").piece_texture(kind)
			if tex:
				var sz := tex.get_size() * s
				draw_texture_rect(tex, Rect2(_o - Vector2(sz.x * 0.5, sz.y - 6.0 * s), sz), false)
			return
		if has_meta("raw") or not SurfaceProps.atlas_draw(self, kind, color, s, variant, _o):
			_draw_one()

	func _draw_one() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = variant
		match kind:
			"tree": _tree(rng)
			"palm": _palm(rng)
			"bush": _bush(rng)
			"tuft": _tuft(rng)
			"flowers": _flowers(rng)
			"pebbles": _pebbles(rng)
			"boulder": _boulder(rng, 1.6)
			"crystal": _crystal(rng)
			"shard": _shard(rng)
			_: _boulder(rng, 1.0)

	## Canopy blob lit from the upper left: dark base, mid tone, highlight.
	func _blob(c: Vector2, r: float, col: Color) -> void:
		draw_circle(c + Vector2(r * 0.12, r * 0.15), r, col.darkened(0.35))
		draw_circle(c, r * 0.92, col)
		draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.45, col.lightened(0.18))

	func _tree(rng: RandomNumberGenerator) -> void:
		SurfaceProps.shadow(self, 24 * s, 10 * s, 0.3, _o)
		var h := rng.randf_range(34, 48) * s
		var lean := rng.randf_range(-5, 5) * s
		draw_line(Vector2.ZERO, Vector2(lean, -h), Color(0.38, 0.26, 0.16), 6.0 * s)
		draw_line(Vector2(-1, 0), Vector2(lean - 1, -h), Color(0.5, 0.36, 0.22), 2.0 * s)
		var top := Vector2(lean, -h - 8 * s)
		var blobs := rng.randi_range(4, 6)
		for k in blobs:  # back-to-front so lower blobs overlap upper ones
			var a := TAU * k / blobs + rng.randf() * 0.6
			var off := Vector2(cos(a) * 15.0, sin(a) * 9.0 - 4.0) * s
			_blob(top + off, rng.randf_range(11, 16) * s, color.lightened(rng.randf_range(-0.08, 0.08)))
		_blob(top + Vector2(0, -6) * s, 15 * s, color.lightened(0.05))

	func _palm(rng: RandomNumberGenerator) -> void:
		SurfaceProps.shadow(self, 20 * s, 8 * s, 0.3, _o)
		var bend := rng.randf_range(10, 22) * s * (1.0 if rng.randf() < 0.5 else -1.0)
		var h := 62.0 * s
		var pts := PackedVector2Array()
		for k in 9:
			var t := k / 8.0
			pts.append(Vector2(bend * t * t, -h * t))
		draw_polyline(pts, Color(0.55, 0.4, 0.24), 6.0 * s, true)
		for k in 8:  # trunk rings
			draw_line(pts[k] + Vector2(-3, 0) * s, pts[k] + Vector2(3, 0) * s, Color(0.42, 0.3, 0.18), 1.5)
		var top := pts[8]
		for k in 6:  # fronds
			var a := -PI + k * PI / 5.0 + rng.randf_range(-0.15, 0.15)
			var tip := top + Vector2(cos(a) * 30.0, sin(a) * 12.0 + 12.0) * s
			var mid := top + (tip - top) * 0.5 + Vector2(0, -8) * s
			draw_polyline(PackedVector2Array([top, mid, tip]), color.darkened(0.15), 4.0 * s, true)
			draw_polyline(PackedVector2Array([top, mid, tip]), color, 2.0 * s, true)
		draw_circle(top + Vector2(0, 3) * s, 4 * s, Color(0.45, 0.32, 0.16))

	func _bush(rng: RandomNumberGenerator) -> void:
		SurfaceProps.shadow(self, 18 * s, 7 * s, 0.3, _o)
		for k in 4:
			_blob(Vector2(rng.randf_range(-11, 11), -8 - rng.randf_range(0, 8)) * s, rng.randf_range(7, 10) * s, color.lightened(rng.randf_range(-0.1, 0.05)))

	func _tuft(rng: RandomNumberGenerator) -> void:
		for k in rng.randi_range(5, 9):
			var x := rng.randf_range(-7, 7) * s
			var h := rng.randf_range(6, 14) * s
			var tip := Vector2(x + rng.randf_range(-4, 4) * s, -h)
			draw_line(Vector2(x, 0), tip, color.lightened(rng.randf_range(-0.15, 0.2)), 1.6, true)

	func _flowers(rng: RandomNumberGenerator) -> void:
		for k in rng.randi_range(4, 7):
			var x := rng.randf_range(-12, 12)
			var y := rng.randf_range(-5, 5)
			var h := rng.randf_range(6, 11)
			draw_line(Vector2(x, y), Vector2(x, y - h), Color(0.3, 0.55, 0.25), 1.2)
			draw_circle(Vector2(x, y - h), 2.6, color)
			draw_circle(Vector2(x, y - h), 1.0, Color(1, 1, 0.8))

	func _pebbles(rng: RandomNumberGenerator) -> void:
		for k in rng.randi_range(3, 6):
			var c := Vector2(rng.randf_range(-16, 16), rng.randf_range(-7, 7))
			var r := rng.randf_range(2.0, 4.5)
			draw_set_transform(_o + c, 0.0, Vector2(1.0, 0.6))
			draw_circle(Vector2(0.6, 0.8), r, color.darkened(0.4))
			draw_circle(Vector2.ZERO, r, color)
			draw_circle(Vector2(-r * 0.3, -r * 0.3), r * 0.45, color.lightened(0.25))
			draw_set_transform(_o)

	func _boulder(rng: RandomNumberGenerator, size_k: float) -> void:
		var k := s * size_k
		SurfaceProps.shadow(self, 20 * k, 8 * k, 0.3, _o)
		var pts := PackedVector2Array()
		var n := rng.randi_range(6, 8)
		for i in n:
			var a := PI + PI * i / (n - 1)
			pts.append(Vector2(cos(a) * 18.0, sin(a) * rng.randf_range(16, 24) - 2.0) * k)
		draw_colored_polygon(pts, color.darkened(0.15))
		# Lit upper-left face and a dark right face.
		var lit := PackedVector2Array([pts[0], pts[1], pts[2], Vector2(-2, -10) * k])
		draw_colored_polygon(lit, color.lightened(0.15))
		var dark := PackedVector2Array([pts[n - 1], pts[n - 2], Vector2(4, -6) * k])
		draw_colored_polygon(dark, color.darkened(0.35))
		draw_line(Vector2(-4, -8) * k, Vector2(3, -2) * k, color.darkened(0.4), 1.2)

	func _crystal(rng: RandomNumberGenerator) -> void:
		SurfaceProps.shadow(self, 16 * s, 6 * s, 0.3, _o)
		draw_circle(Vector2(0, -16) * s, 22 * s, Color(color, 0.08))  # faint glow
		for k in rng.randi_range(3, 5):
			var x := rng.randf_range(-12, 12) * s
			var h := rng.randf_range(18, 40) * s
			var w := rng.randf_range(4, 7) * s
			var lean := rng.randf_range(-5, 5) * s
			var pts := PackedVector2Array([Vector2(x - w, 0), Vector2(x + w, 0), Vector2(x + w * 0.6 + lean, -h), Vector2(x + lean, -h - w * 1.6), Vector2(x - w * 0.6 + lean, -h)])
			draw_colored_polygon(pts, Color(color, 0.88))
			draw_colored_polygon(PackedVector2Array([Vector2(x - w, 0), Vector2(x, 0), Vector2(x + lean, -h - w * 1.6), Vector2(x - w * 0.6 + lean, -h)]), Color(color.lightened(0.35), 0.9))
			draw_line(Vector2(x, 0), Vector2(x + lean, -h - w * 1.4), Color(1, 1, 1, 0.7), 1.2)

	func _shard(rng: RandomNumberGenerator) -> void:
		SurfaceProps.shadow(self, 10 * s, 4 * s, 0.3, _o)
		var h := rng.randf_range(14, 26) * s
		var lean := rng.randf_range(-8, 8) * s
		var pts := PackedVector2Array([Vector2(-6, 0) * s, Vector2(6, 0) * s, Vector2(lean, -h)])
		draw_colored_polygon(pts, Color(color, 0.85))
		draw_colored_polygon(PackedVector2Array([Vector2(-6, 0) * s, Vector2(0, 0), Vector2(lean, -h)]), Color(color.lightened(0.3), 0.9))


## Flat ground cover (grass tufts, flowers, pebbles, small rocks, shards)
## never needs sorting against characters, so it isn't a node per prop: the
## surface keeps it as PropData, and one PropBatch per map chunk draws all of
## a chunk's props in a single canvas item (17 000 nodes -> ~100).
const FLAT := ["tuft", "flowers", "pebbles", "rock", "shard"]


class PropData extends RefCounted:
	var kind := "rock"
	var color := Color.GRAY
	var s := 1.0
	var variant := 0
	var position := Vector2.ZERO
	var batch: Node2D
	var chunk := Vector2i(-1, -1)     # its scenery chunk (streamed), or (-1, -1)
	var lift := 0.0                   # drawn this much higher (the ground's elevation)


class PropBatch extends Prop:
	var items: Array = []

	func _draw() -> void:
		for e in items:
			kind = e.kind
			color = e.color
			s = e.s
			variant = e.variant
			_o = e.position - position - Vector2(0, e.lift)
			if SurfaceProps.atlas_draw(self, kind, color, s, variant, _o):
				continue
			draw_set_transform(_o)
			_draw_one()
			draw_set_transform(Vector2.ZERO)


# --- Prop atlas -------------------------------------------------------------------
# Props are vector art (dozens of circles and lines each, each a draw call).
# When a surface is built, every distinct look (kind, colour, one of VARIANTS
# shapes) is rendered once into one atlas texture; props then draw a single
# textured rectangle from it, and all of them batch into a few draw calls.

const ATLAS_SCALE := 1.6                  # rendered at the largest prop scale
const CELL := Vector2(176, 176)           # atlas cell (px)
const ANCHOR := Vector2(88, 150)          # the prop's foot in its cell
const VARIANTS := 6
static var _atlas: Texture2D
static var _cells := {}                   # key -> Rect2 in the atlas
static var _atlas_mat: ShaderMaterial
## Small ground cover is rendered at its usual size (no downscaling blur).
const SMALL := ["tuft", "flowers", "pebbles"]


static func _ascale(kind: String) -> float:
	return 1.0 if kind in SMALL else ATLAS_SCALE


static func atlas_key(kind: String, color: Color, variant: int) -> String:
	var q := Color(snappedf(color.r, 0.07), snappedf(color.g, 0.07), snappedf(color.b, 0.07))
	return "%s|%s|%d" % [kind, q.to_html(false), posmod(variant, VARIANTS)]


## The material atlas-drawn props share (un-premultiplies the atlas).
static func atlas_material() -> ShaderMaterial:
	if _atlas_mat == null:
		_atlas_mat = ShaderMaterial.new()
		_atlas_mat.shader = preload("res://shaders/unpremult.gdshader")
	return _atlas_mat


## Draws the prop from the atlas onto `ci` at `origin`; false if it isn't there.
static func atlas_draw(ci: CanvasItem, kind: String, color: Color, scale_: float, variant: int, origin: Vector2) -> bool:
	if _atlas == null:
		return false
	var r = _cells.get(atlas_key(kind, color, variant))
	if r == null:
		return false
	var k := scale_ / _ascale(kind)
	ci.draw_texture_rect_region(_atlas, Rect2(origin - ANCHOR * k, CELL * k), r)
	return true


## Renders every look in `looks` ([kind, colour, variant] ...) into the atlas.
## Awaitable; `host` must be in the tree (a SubViewport renders it).
static func build_atlas(host: Node, looks: Array) -> void:
	var keys := {}
	for l in looks:
		var key := atlas_key(l[0], l[1], l[2])
		if not keys.has(key):
			keys[key] = l
	_atlas = null
	_cells = {}
	# No renderer (headless: tests, servers): nothing would ever be drawn into
	# the viewport - props simply keep drawing their vector art.
	if keys.is_empty() or DisplayServer.get_name() == "headless":
		return
	var cols := 11
	var rows := ceili(float(keys.size()) / cols)
	var vp := SubViewport.new()
	vp.size = Vector2i(int(CELL.x) * cols, int(CELL.y) * rows)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	var cells := {}
	var i := 0
	for key in keys:
		var l: Array = keys[key]
		var cell := Vector2(i % cols, i / cols) * CELL
		var p := Prop.new()
		p.kind = l[0]
		p.color = l[1]
		p.s = _ascale(p.kind)
		p.variant = posmod(int(l[2]), VARIANTS) * 7919 + 13
		p.set_meta("raw", true)
		p.position = cell + ANCHOR
		vp.add_child(p)
		cells[key] = Rect2(cell, CELL)
		i += 1
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return
	# (Its mipmaps made on a worker thread: on the main thread, with the read
	# back, a 17 ms frame in the landing.)
	var task := WorkerThreadPool.add_task(img.generate_mipmaps)
	while not WorkerThreadPool.is_task_completed(task):
		await host.get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_atlas = ImageTexture.create_from_image(img)
	_cells = cells
