class_name CosmosLoot
extends Node3D
## What the dead leave behind (the 3D game): every enemy, person and animal
## that dies drops its loot by its body - a leather pouch tied with cord, its
## bronze clasp glinting now and then (one small mesh, shared; loot.gdshader) -
## its contents by what it was (contents_for):
##   animals - game meat, raw hides, bones; the alien ones (the worlds' own
##     designs, the glowing, the insects) cybernetic matter, a monster's titan
##     bones and void crystals; a caravan's pack animal its load too;
##   pirates and raiders - drachmas, rifle charges, weapon parts, ore;
##   the dead of the caves and dungeons - old coins (drachmas), relic shards,
##     Linear tablets, amber; the demons chimera embers (their lord: a hoard);
##   townsfolk and the road's people - their goods: a trader's wares, a
##     courier's letters, a pilgrim's incense, a guard's charges and pay.
## Walk up to it and take it (the prompt "Loot the ...": Cosmos.terminal_here ->
## prompt(); use_terminal "loot" -> take()): into your inventory, what fits, the
## event log noting it; what doesn't fit stays in it. Gone after LAST s (a road's
## wreck - CosmosCaravans - after LAST_WRECK). Nothing of it saved.
## It finds the dead itself (the creatures' and npcs' lists, a few times a
## second); Cosmos.creature_died / npc_died may call drop_for too (once a body).

const REACH := 2.3              # m: close enough to take it
const LAST := 240.0             # s it lies there
const LAST_WRECK := 900.0       # (a caravan's remains, robbed out of your sight)
const LOOT_CLASS := "res://scripts/world/life/cosmos_loot.gd"
const SHADER := preload("res://shaders/world/loot.gdshader")

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial

var cosmos: Node
var drops: Array = []           # {node, contents: {id: n}, title, t, pl}
var _scan := 0.0
var _rng := RandomNumberGenerator.new()


## The Cosmos's loot (made, as its child, the first time it's asked for).
static func of(c: Node) -> CosmosLoot:
	var n := c.get_node_or_null("Loot") as CosmosLoot
	if n == null:
		n = load(LOOT_CLASS).new()
		n.name = "Loot"
		n.cosmos = c
		c.add_child(n)
	return n


## The prompt for the loot in reach ([text, "loot"]), or [] (Cosmos.terminal_here).
static func prompt(c: Node) -> Array:
	var e := of(c).near()
	if e.is_empty():
		return []
	return ["Loot the %s" % str(e["title"]), "loot"]


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.2
		if cosmos:
			for list in [cosmos.get("creatures"), cosmos.get("npcs")]:
				if list == null:
					continue
				for x in list:
					if is_instance_valid(x) and x.get("dead") and not x.has_meta("loot_dropped"):
						drop_for(x)
	var i := 0
	while i < drops.size():
		var e: Dictionary = drops[i]
		e["t"] = float(e["t"]) - delta
		if float(e["t"]) <= 0.0 or not is_instance_valid(e["node"]):
			if is_instance_valid(e["node"]):
				(e["node"] as Node).queue_free()
			drops.remove_at(i)
		else:
			i += 1


## The loot of `body` (a CosmosCreature or CosmosNpc that's died) dropped by it - once.
func drop_for(body: Node3D) -> Dictionary:
	if body == null or not is_instance_valid(body) or body.has_meta("loot_dropped"):
		return {}
	body.set_meta("loot_dropped", true)
	var pl: CosmosPlanet = body.get("planet")
	var parent: Node3D = body.get("dungeon") if body.get("dungeon") != null else pl
	if parent == null:
		return {}
	var up: Vector3 = body.up() if body.has_method("up") else Vector3.UP
	var at := body.global_position
	if pl and body.get("dungeon") == null and not body.get("in_cave"):
		var local := at - pl.global_position
		var d := local.normalized()
		at = pl.global_position + d * (pl.radius + maxf(pl.shape.height(d), 0.0))   # (on the ground - a bird's fallen)
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	at += side * 0.5
	var g = body.get("goods")
	var big: bool = body.has_meta("goods") or (g is Dictionary and not (g as Dictionary).is_empty())
	return drop(parent, at, up, title_of(body), contents_for(body, _rng), LAST, 1.6 if big else 1.25, pl)


## A pouch of `contents` at `at` (global) on `parent` (it moves with it).
func drop(parent: Node3D, at: Vector3, up: Vector3, title: String, contents: Dictionary, last := LAST, size := 1.0, pl: CosmosPlanet = null) -> Dictionary:
	var mi := MeshInstance3D.new()
	mi.name = "Loot"
	mi.mesh = mesh()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 160.0
	parent.add_child(mi)
	var f := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized().rotated(up, _rng.randf() * TAU)
	mi.global_transform = Transform3D(Basis.looking_at(f, up).scaled(Vector3.ONE * size), at)
	var e := {"node": mi, "contents": contents, "title": title, "t": last, "pl": pl}
	drops.append(e)
	return e


## A caravan's remains (CosmosCaravans: robbed where you didn't see): on planet-local `local`.
func drop_wreck(pl: CosmosPlanet, local: Vector3, title: String, contents: Dictionary) -> Dictionary:
	var d := local.normalized()
	var at := pl.global_position + d * (pl.radius + maxf(pl.shape.height(d), 0.0))
	return drop(pl, at, d, title, contents, LAST_WRECK, 1.5, pl)


## The loot within your reach (the nearest), or {}.
func near() -> Dictionary:
	var w: Node3D = cosmos.get("walker") if cosmos else null
	if w == null or w.get("deck") != null:
		return {}
	var best := {}
	var bd := REACH
	for e in drops:
		if not is_instance_valid(e["node"]):
			continue
		var dd := (e["node"] as Node3D).global_position.distance_to(w.global_position)
		if dd < bd:
			bd = dd
			best = e
	return best


## Take the loot in reach: you stoop for it (the walker's pick-up), then it's yours.
func take() -> void:
	var e := near()
	if e.is_empty():
		return
	var w: Node = cosmos.walker
	if w.has_method("hands") and w.has_method("busy") and not w.busy() and not w.get("carrying"):
		w.hands("pick_up", func(): give(e))
	else:
		give(e)


## Its contents into your inventory (what fits; the rest stays in it): the event log notes them.
func give(e: Dictionary) -> String:
	if not drops.has(e):
		return ""
	var data: Node = CosmosGame.data
	var got: Array = []
	var left: Array = []
	var contents: Dictionary = e["contents"]
	for id in contents.keys():
		var n := int(contents[id])
		if n <= 0:
			contents.erase(id)
			continue
		if id == "credits":
			if data:
				data.add_credits(n)
			got.append("%d drachmas" % n)
			contents.erase(id)
			continue
		var k := n
		if data and data.has_method("room_for") and Items.is_cargo(id):
			k = mini(n, int(data.room_for(id)))
		if k > 0 and data:
			data.add_item(id, k)
		if k > 0:
			got.append("%d %s" % [k, Items.display_name(id)])
		if k < n:
			contents[id] = n - k
			left.append(Items.display_name(id))
		else:
			contents.erase(id)
	var text := "Looted the %s: %s" % [str(e["title"]), ", ".join(got) if not got.is_empty() else "nothing you have room for"]
	if not left.is_empty():
		text += " (no room for the %s)" % ", ".join(left)
	if cosmos and cosmos.get("hud"):
		cosmos.hud.flash(text, 4.0)
	else:
		GameLog.post(text, "good")
	if contents.is_empty():
		if is_instance_valid(e["node"]):
			(e["node"] as Node).queue_free()
		drops.erase(e)
	return text


# --- What it was, what it leaves -----------------------------------------------------------

## How the prompt names it ("Loot the ...").
static func title_of(body: Node) -> String:
	if body.has_meta("loot_title"):
		return str(body.get_meta("loot_title"))
	if body is CosmosCreature:
		var k: Dictionary = (body as CosmosCreature).kind
		return str(k.get("name", "animal")) if k.has("id") else str(k.get("name", "animal"))
	var role := str(body.get("role"))
	match role:
		"pirate":
			return "pirate"
		"raider":
			return "raider"
		"skeleton":
			return "skeleton warrior"
		"demon":
			return "demon lord" if float(body.get("scale_k")) > 1.5 else "demon"
		"guard":
			return "caravan guard" if body is CosmosTraveller else "guard"
		"trader", "courier", "pilgrim", "vendor", "pilot":
			return role
	return str(body.get("label")).to_lower() if str(body.get("label")) != "" else "body"


## A body's loot: item id -> how many ("credits": drachmas). Never empty.
static func contents_for(body: Node, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var add := func(id: String, n: int) -> void:
		if n > 0:
			out[id] = int(out.get(id, 0)) + n
	var carried = body.get_meta("goods") if body.has_meta("goods") else body.get("goods")
	if carried is Dictionary:
		for id in carried:
			add.call(str(id), int(carried[id]))
	if body is CosmosCreature:
		var k: Dictionary = (body as CosmosCreature).kind
		var size := float(k.get("size", 1.0)) * float(k.get("scale", 1.0))
		var legs := int(k.get("legs", 4))
		var alien: bool = not k.has("id") or float(k.get("glow", 0.0)) > 0.0 or legs >= 6
		var monster: bool = k.get("monster", false)
		var drift: bool = float(k.get("alt", 0.0)) > 0.0 and legs == 0
		if not drift:
			add.call("game_meat", maxi(1, roundi(size * rng.randf_range(1.0, 2.0))))
		if legs in [2, 4] and float(k.get("shell", 0.0)) <= 0.0:
			add.call("raw_hide", 1 + (1 if size > 1.3 else 0))
		if legs > 0 or size > 0.8:
			add.call("beast_bone", 1 + (1 if size > 1.6 or rng.randf() < 0.3 else 0))
		if alien:
			add.call("cyber_matter", rng.randi_range(1, 2))
			if rng.randf() < 0.15:
				add.call("xeno_spores", 1)
		if monster:
			add.call("titan_bones", 1)
			if rng.randf() < 0.5:
				add.call("void_crystals", 1)
	else:
		var role := str(body.get("role"))
		var weapon := str(body.get("weapon"))
		match role:
			"pirate", "raider":
				add.call("credits", rng.randi_range(20, 120))
				add.call("rifle_charges", rng.randi_range(1, 3))
				if rng.randf() < 0.5:
					add.call(["scrap_electronics", "targeting_scopes", "capacitors"][rng.randi() % 3], 1)
				if rng.randf() < 0.5:
					add.call(["iron_ore", "copper_ore", "titanium_ore", "tin_ore"][rng.randi() % 4], rng.randi_range(1, 3))
			"skeleton":
				add.call("credits", rng.randi_range(30, 150))
				if rng.randf() < 0.4:
					add.call("relic_shards", 1)
				if rng.randf() < 0.25:
					add.call("linear_tablets", 1)
				if rng.randf() < 0.2:
					add.call("amber", 1)
			"demon":
				if float(body.get("scale_k")) > 1.5:
					add.call("credits", rng.randi_range(600, 1200))
					add.call("void_crystals", rng.randi_range(1, 2))
					add.call("relic_shards", 2)
					add.call("chimera_embers", 2)
				else:
					add.call("credits", rng.randi_range(80, 260))
					add.call("chimera_embers", 1)
					if rng.randf() < 0.5:
						add.call("relic_shards", 1)
			"guard":
				add.call("credits", rng.randi_range(10, 60))
				if weapon == "rifle":
					add.call("rifle_charges", rng.randi_range(1, 2))
				elif weapon == "bow":
					add.call("capacitors", 1)
				if rng.randf() < 0.15:
					add.call("bronze_shields", 1)
			"trader":
				add.call("credits", rng.randi_range(40, 160))
			"courier":
				add.call("credits", rng.randi_range(20, 80))
				add.call("papyrus", 1)
				if rng.randf() < 0.3:
					add.call("star_maps", 1)
			"pilgrim":
				add.call("credits", rng.randi_range(5, 30))
				add.call("incense", rng.randi_range(1, 2))
				if rng.randf() < 0.25:
					add.call("statuettes", 1)
			_:
				add.call("credits", rng.randi_range(15, 90))
				if rng.randf() < 0.4:
					add.call(["wine", "olive_oil", "figs", "honey"][rng.randi() % 4], 1)
	for id in out.keys():   # (only what the catalogue knows)
		if id != "credits" and not Items.exists(id):
			out.erase(id)
	if out.is_empty():
		out["credits"] = rng.randi_range(5, 25)
	return out


# --- Its look ------------------------------------------------------------------------------

## The pouch (shared): a lathed leather sack, lumpy, tied at the neck with
## cord, its mouth flared, a bronze clasp on the cord - ~0.36 m across.
static func mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var leather := Color(0.36, 0.22, 0.12, 1.0)
	var cord := Color(0.62, 0.52, 0.36, 0.5)
	# [radius, height, colour]
	var prof := [[0.0, 0.0, leather], [0.11, 0.008, leather], [0.165, 0.05, leather], [0.18, 0.11, leather], [0.16, 0.175, leather],
		[0.1, 0.225, leather], [0.062, 0.245, cord], [0.06, 0.262, cord], [0.075, 0.28, leather], [0.112, 0.312, leather],
		[0.09, 0.322, leather], [0.0, 0.3, leather]]
	var segs := 14
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var nors := PackedVector3Array()
	var rows := prof.size()
	for r in rows:
		for s in segs + 1:
			var a := TAU * s / segs
			var lump := 1.0 + 0.07 * sin(a * 3.0 + r * 1.3) + 0.04 * sin(a * 5.0 - r)   # (a sack, not a vase)
			if r >= 8:
				lump += 0.12 * sin(a * 7.0)   # (its mouth's ruffle)
			var rad: float = float(prof[r][0]) * lump
			verts.append(Vector3(cos(a) * rad, float(prof[r][1]), sin(a) * rad * 0.88))
			cols.append(prof[r][2])
	for r in rows:   # (normals: across the profile and round it)
		for s in segs + 1:
			var k := r * (segs + 1) + s
			var up := verts[mini(r + 1, rows - 1) * (segs + 1) + s] - verts[maxi(r - 1, 0) * (segs + 1) + s]
			var a := TAU * s / segs
			var round := Vector3(-sin(a), 0, cos(a))
			var n := up.cross(round).normalized()
			if n.dot(Vector3(cos(a), 0, sin(a))) < 0.0 and r > 0 and r < rows - 1:
				n = -n
			if r == 0:
				n = Vector3.DOWN
			elif r == rows - 1:
				n = Vector3.UP
			nors.append(n)
	var idx := PackedInt32Array()
	for r in rows - 1:
		for s in segs:
			var a := r * (segs + 1) + s
			var b := a + 1
			var c := a + segs + 1
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	# The clasp: a bronze block on the cord at the front.
	var base := verts.size()
	var bronze := Color(0.62, 0.42, 0.16, 0.0)
	var cs := Vector3(0.03, 0.026, 0.014)
	var cc := Vector3(0, 0.254, 0.062 * 0.88 + 0.012)
	for z in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for x in [-1.0, 1.0]:
				verts.append(cc + Vector3(x, y, z) * cs)
				cols.append(bronze)
				nors.append(Vector3(x, y, z).normalized())
	for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1], [2, 3, 7, 6]]:
		idx.append_array([base + q[0], base + q[1], base + q[2], base + q[0], base + q[2], base + q[3]])
	# (every triangle wound to face out: front faces clockwise seen from outside)
	var mid := Vector3(0, 0.16, 0)
	for k in range(0, idx.size(), 3):
		var p0 := verts[idx[k]]
		var p1 := verts[idx[k + 1]]
		var p2 := verts[idx[k + 2]]
		var cen := (p0 + p1 + p2) / 3.0
		var out_dir := (cen - (cc if idx[k] >= base else mid))
		if (p1 - p0).cross(p2 - p0).dot(out_dir) > 0.0:
			var t := idx[k + 1]
			idx[k + 1] = idx[k + 2]
			idx[k + 2] = t
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nors
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _mesh


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
	return _mat
