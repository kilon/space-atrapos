class_name CosmosBuilds
extends Node3D
## Your buildings (Cosmos): the structures on the world you're on - each a
## CosmosStructure, kept in the save (CosmosGame.extra "structures": planet
## id -> [record]) and raised again when you come back - and the builder, the
## automaton's building tool (Inventory "tool:build"), in hand:
##   - aim: a translucent preview of the piece where it would go, snapped to
##     the nearest socket of what's built (BuildPlan.snap) - green when it fits,
##     red when it doesn't (the HUD says why: no support, too far from one, the
##     ground too high, its socket taken, what it costs and you lack);
##   - a click places it (its cost taken: what you carry first, then the
##     hold); held and dragged, a run of them - a wall's length, a floor's
##     rectangle - placed on letting go;
##   - K (or the middle button) turns it (a quarter for squares and stairs, a
##     half for walls and doors, 30 degrees for furniture); P snapping off
##     (furniture and foundations free where you aim); N the build menu (the
##     pieces by category, the tier, the empire's style, a paint);
##   - O the mode: place, demolish (the piece aimed at amber, and what would
##     fall with it; a click takes it down, half its cost back - all of it
##     within a minute), upgrade (the next tier, for the difference), paint.
## Doors, gates, shutters and hatches open with a click (Cosmos.terminal_here);
## a chest keeps things, a bed is where you wake, the workbench and the kiln are
## your ship's fabricator and refinery; the braziers and wall lamps light the
## rooms (the nearest LIGHTS of them).

const REACH := 12.0             # m from you
const JOIN := 9.0               # m: a piece aimed this near a structure's pieces joins it
const LIGHTS := 8
const MODES := ["place", "remove", "upgrade", "paint"]
const MODE_NAMES := {"place": "Build", "remove": "Demolish", "upgrade": "Upgrade", "paint": "Paint"}

var cosmos: Node
var planet: CosmosPlanet
var structures: Array = []

# The builder's state (kept for the run).
static var piece := "foundation"
static var tier := 1
static var style := "minoa"
static var paint := 0
static var mode := "place"
static var snap_on := true
static var turned := 0

var aim_ok := false
var aim_why := ""
var aim_pc := {}                # (place: what would go; other modes: the piece aimed at)
var aim_st: CosmosStructure = null
var aim_falls := 0
var aim_cost := {}
var aim_frame := Transform3D()  # (a new structure's frame, if it starts one)
var placed := 0
var _ghost: MeshInstance3D
var _ghost_key := ""
var _ghosts: Array = []         # (a run's)
var _held := false
var _drag_from := {}
var _drag_st: CosmosStructure = null
var _drag_frame := Transform3D()
var _run: Array = []            # [record] a drag's pieces
var _t := 0.0
var _sync_t := 0.0
var _light_t := 0.0
var _lamps: Array = []
var _pick_cache := [-1, null, 0]


func _ready() -> void:
	name = "Builds"
	_ghost = MeshInstance3D.new()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	if not BuildKit.STYLES.has(style):
		style = "minoa"


static func pid_of(pl: CosmosPlanet) -> String:
	return str(pl.rec.get("id", pl.name))


## The world's records in the save.
static func records(pid: String) -> Array:
	var all: Dictionary = CosmosGame.extra.get("structures", {})
	if not all.has(pid):
		all[pid] = []
		CosmosGame.extra["structures"] = all
	return all[pid]


func tool_out() -> bool:
	var w: Node = cosmos.get("walker") if cosmos else null
	return w != null and w.get("deck") == null and ToolbarUse.held(cosmos) == "tool:build"


func _process(delta: float) -> void:
	if cosmos == null:
		return
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.5
		_sync_planet()
	_light_t -= delta
	if _light_t <= 0.0:
		_light_t = 0.4
		_lights()
	if tool_out() and planet:
		_t -= delta
		if _t <= 0.0:
			_t = 1.0 / 30.0   # (the aim looked at 30 times a second, not every frame)
			update_aim()
		_ride()
	elif _ghost.visible or not _ghosts.is_empty():
		_ghost.visible = false
		_clear_run()
		_held = false


## The structures of the world you're on (or flying low over) raised; another world's let go.
func _sync_planet() -> void:
	var pl: CosmosPlanet = null
	var w: Node = cosmos.get("walker")
	if w and w.get("planet"):
		pl = w.planet
	elif cosmos.has_method("life_planet"):
		pl = cosmos.life_planet()
	if pl == planet:
		return
	for st in structures:
		if is_instance_valid(st):
			st.queue_free()
	structures = []
	planet = pl
	if pl == null:
		return
	for rec in records(pid_of(pl)):
		_raise(rec)


func _raise(rec: Dictionary) -> CosmosStructure:
	var st := CosmosStructure.new()
	st.setup(planet, rec)
	planet.add_child(st)
	st.transform = CosmosStructure.frame_of(rec)
	structures.append(st)
	return st


## Everything built raised again (a loaded game: the records changed under it).
func reload() -> void:
	var pl := planet
	planet = null
	if pl:
		for st in structures:
			if is_instance_valid(st):
				st.queue_free()
		structures = []
		planet = pl
		for rec in records(pid_of(pl)):
			_raise(rec)


# --- Aiming ------------------------------------------------------------------------------

func _ray() -> Array:
	var cam: Camera3D = cosmos.cam
	return [cam.global_position, -cam.global_basis.z]


## What's under the sights, and what the builder would do there.
func update_aim() -> void:
	var w: Node3D = cosmos.walker
	var r := _ray()
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	var limit := REACH + o.distance_to(w.global_position)
	if mode != "place":
		_aim_piece(o, d, limit)
		return
	# Where the sights meet something: a structure's block or the ground.
	var t := limit
	var hit_st: CosmosStructure = null
	for st: CosmosStructure in structures:
		if not st.near(st.to_local(w.global_position), REACH + 6.0):
			continue
		var h: Array = st.ray_hit(st.to_local(o), st.global_basis.inverse() * d, t)
		if float(h[0]) < t:
			t = float(h[0])
			hit_st = st
	var g := ground_hit(o, d, t)
	if g != Vector3.ZERO:
		t = o.distance_to(g)
		hit_st = null
	var at := o + d * t
	if at.distance_to(w.global_position) > REACH:
		at = w.global_position + (at - w.global_position).limit_length(REACH)
	# The structure it joins: the one hit, else the nearest with a piece near.
	var st: CosmosStructure = hit_st
	if st == null:
		var bd := JOIN
		for s2: CosmosStructure in structures:
			var l := s2.to_local(at)
			if not s2.near(l):
				continue
			for pc in s2.plan.pieces:
				var dd := BuildKit.vec(pc["p"]).distance_to(l)
				if dd < bd:
					bd = dd
					st = s2
	aim_st = st
	var pc := {}
	var I := BuildKit.info(piece)
	if st:
		var l := st.to_local(at)
		if snap_on:
			pc = st.plan.snap(piece, l, turned, 3.6, st.to_local(o), (st.global_basis.inverse() * d).normalized())
		elif I["kind"] == "free" or I.get("found", false):
			pc = st.plan.snap_free(piece, l, turned, true)
			if I.get("found", false):
				pc["p"] = BuildKit.arr(Vector3(l.x, 0.0, l.z))
		if pc.is_empty() and I["kind"] == "free":
			pc = st.plan.snap_free(piece, l, turned)
	else:
		# (no structure there: a foundation, or furniture on the ground, starts one)
		if _held and not _drag_from.is_empty() and _drag_st == null and I.get("found", false):
			# (dragging out a new one's foundations: on the frame where the drag began, its grid)
			aim_frame = _drag_frame
			var lq := aim_frame.affine_inverse() * (planet.global_transform.affine_inverse() * at)
			pc = {"t": piece, "p": [snappedf(lq.x, BuildKit.CELL), 0.0, snappedf(lq.z, BuildKit.CELL)], "r": 0}
		elif I.get("found", false) or (I["kind"] == "free" and not I.get("wallfix", false)):
			aim_frame = new_frame(at, -cam_basis().z)
			pc = {"t": piece, "p": [0.0, 0.0, 0.0], "r": posmod(turned, 12) if I["kind"] == "free" else 0}
			if I.get("found", false):
				aim_frame.origin += aim_frame.basis.y * _new_top(at, aim_frame, str(I["shape"]))
	aim_pc = pc
	if pc.is_empty():
		aim_ok = false
		aim_why = "Nothing to fix it to here" if st == null else "No place for it there"
		_ghost.visible = false
		_clear_run()
		return
	pc["m"] = tier
	pc["s"] = style
	pc["c"] = paint
	aim_why = why(st, pc)
	aim_cost = BuildKit.cost(piece, tier)
	aim_ok = aim_why == ""
	if _held and not _drag_from.is_empty() and st == _drag_st:
		_update_run(pc)
	_show_ghost(st, pc, "ok" if aim_ok else "bad")


## Why `pc` can't go on `st` (null: a new structure at aim_frame), "" if it can.
func why(st: CosmosStructure, pc: Dictionary, extra := {}) -> String:
	var fr: Transform3D = st.transform if st else aim_frame
	var p := fr * BuildKit.vec(pc["p"])
	if planet.shape.cleared(p.normalized()) and not BuildKit.free_build:
		return "Not in a town"
	var w: Node3D = cosmos.walker
	if w and (planet.global_transform * p).distance_to(w.global_position) > REACH + 2.0:
		return "Too far"
	var r := ""
	if st:
		r = st.plan.check(pc)
	else:
		var tmp := BuildPlan.new([])
		tmp.ground = func(x: float, z: float) -> float: return _ground_in(aim_frame, x, z)
		r = tmp.check(pc)
	if r != "":
		return r
	if BuildKit.free_build:
		return ""
	var c := BuildKit.cost(str(pc["t"]), int(pc.get("m", 1)))
	for k in extra:
		c[k] = int(c.get(k, 0)) + int(extra[k])
	for k in c:
		if have(k) < int(c[k]):
			return "Needs %s - you have %d %s" % [BuildKit.cost_text(c), have(k), Items.display_name(k)]
	return ""


## The piece under the sights (demolish, upgrade, paint): aim_pc / aim_st, and what falls with it.
func _aim_piece(o: Vector3, d: Vector3, limit: float) -> void:
	var best := INF
	var bi := -1
	var bs: CosmosStructure = null
	for st: CosmosStructure in structures:
		var lo := st.to_local(o)
		if not st.near(lo, limit + 6.0):
			continue
		var h: Array = st.plan.pick(lo, st.global_basis.inverse() * d, minf(best, limit))
		if int(h[0]) >= 0 and float(h[1]) < best:
			best = float(h[1])
			bi = int(h[0])
			bs = st
	_clear_run()
	if bi < 0:
		aim_pc = {}
		aim_st = null
		aim_ok = false
		aim_why = "Aim at a piece"
		_ghost.visible = false
		return
	var pc: Dictionary = bs.plan.pieces[bi]
	aim_pc = pc
	aim_st = bs
	aim_ok = true
	aim_why = ""
	aim_cost = {}
	match mode:
		"remove":
			if _pick_cache[0] != bi or _pick_cache[1] != bs or _pick_cache[2] != bs.plan.pieces.size():
				_pick_cache = [bi, bs, bs.plan.pieces.size(), bs.plan.falling(bi).size() - 1]
			aim_falls = int(_pick_cache[3])
			aim_cost = BuildKit.refund(pc, Time.get_unix_time_from_system())
		"upgrade":
			var m := int(pc.get("m", 1))
			if m >= BuildKit.TIERS.size() - 1:
				aim_ok = false
				aim_why = "Bronze already - as strong as it gets"
			else:
				aim_cost = upgrade_cost(pc)
				for k in aim_cost:
					if have(k) < int(aim_cost[k]) and not BuildKit.free_build:
						aim_ok = false
						aim_why = "Needs %s" % BuildKit.cost_text(aim_cost)
		"paint":
			if int(pc.get("c", 0)) == paint:
				aim_ok = false
				aim_why = "Already that colour"
	var show := pc.duplicate()
	if mode == "upgrade" and aim_ok:
		show["m"] = int(pc.get("m", 1)) + 1
	if mode == "paint":
		show["c"] = paint
	_show_ghost(bs, show, "pick" if mode == "remove" else ("ok" if aim_ok else "bad"), 1.02)


## The next tier's cost less a third of this one's (what's reused).
static func upgrade_cost(pc: Dictionary) -> Dictionary:
	var m := int(pc.get("m", 1))
	var c := BuildKit.cost(str(pc["t"]), m + 1)
	var old := BuildKit.cost(str(pc["t"]), m)
	for k in old:
		if c.has(k):
			c[k] = maxi(0, int(c[k]) - floori(int(old[k]) / 3.0))
	return c


func cam_basis() -> Basis:
	return (cosmos.cam as Camera3D).global_basis


## A new structure's frame at global `at` (planet-local origin), x across `look`.
func new_frame(at: Vector3, look: Vector3) -> Transform3D:
	var o := at - planet.global_position
	var up := o.normalized()
	var f := (look - up * look.dot(up))
	if f.length() < 0.01:
		f = up.cross(Vector3.RIGHT)
	f = f.normalized()
	var x := f.cross(up).normalized()   # (its +z the way you look: x your right... turned so -z faces you)
	return Transform3D(Basis(x, up, x.cross(up)), o)


## A first foundation's top over the frame's origin: level just above its highest corner.
func _new_top(at: Vector3, fr: Transform3D, shape: String) -> float:
	var hi := -INF
	for q in BuildKit.outline(shape):
		hi = maxf(hi, _ground_in(fr, q.x, q.y))
	hi = maxf(hi, _ground_in(fr, 0.0, 0.0))
	return hi + 0.3


func _ground_in(fr: Transform3D, x: float, z: float) -> float:
	var q := fr * Vector3(x, 0.0, z)
	var hgt: float = planet.shape.floor_below(q) if planet.shape.carved_near(q) else planet.shape.height(q.normalized())
	return (planet.radius + hgt) - q.length()


## Where a line from `o` along `dir` meets the ground within `reach` (global), or ZERO.
func ground_hit(o: Vector3, dir: Vector3, reach: float) -> Vector3:
	var c := planet.global_position
	var shape := planet.shape
	var t0 := 0.0
	var t := 0.5
	while t <= reach:
		if shape.density(o + dir * t - c) < 0.0:
			for k in 6:
				var mid := (t0 + t) * 0.5
				if shape.density(o + dir * mid - c) < 0.0:
					t = mid
				else:
					t0 = mid
			return o + dir * t
		t0 = t
		t += 0.5
	return Vector3.ZERO


# --- The preview ---------------------------------------------------------------------

static var _ghost_meshes := {}


static func ghost_mesh(pc: Dictionary) -> ArrayMesh:
	var k := "%s|%d|%s" % [pc["t"], int(pc.get("m", 1)), pc.get("s", "minoa")]
	if _ghost_meshes.has(k):
		return _ghost_meshes[k]
	var b := CosmosTown.Builder.new()
	var q := pc.duplicate()
	q["p"] = [0.0, 0.0, 0.0]
	q["r"] = 0
	if not q.has("d"):
		q["d"] = 1.0
	var res := BuildKit.emit(b, q, true)
	for mv: Dictionary in res["movers"]:   # (its leaves shut, in the preview too)
		var lb: CosmosTown.Builder = mv["lb"]
		var xf: Transform3D = mv["xf"]
		var base := b.verts.size()
		b.verts.append_array(xf * lb.verts)
		b.norms.append_array(Transform3D(xf.basis, Vector3.ZERO) * lb.norms)
		b.cols.append_array(lb.cols)
		for i in lb.idx:
			b.idx.append(i + base)
	var m := b.mesh() if b.verts.size() > 0 else ArrayMesh.new()
	if _ghost_meshes.size() > 120:
		_ghost_meshes.clear()
	_ghost_meshes[k] = m
	return m


func _show_ghost(st: CosmosStructure, pc: Dictionary, look: String, grow := 1.0) -> void:
	_ghost.mesh = ghost_mesh(pc)
	_ghost.material_override = BuildKit.ghost_material(look)
	var fr: Transform3D = st.global_transform if st else planet.global_transform * aim_frame
	var p := BuildKit.vec(pc["p"])
	_ghost.global_transform = fr * Transform3D(BuildKit.turn(int(pc.get("r", 0))).scaled(Vector3.ONE * grow), p)
	_ghost.set_meta("on", planet.global_transform.affine_inverse() * _ghost.global_transform)
	_ghost.visible = true


# --- Placing -------------------------------------------------------------------------

## The fire button (the builder in hand): pressed - a placement (or the start
## of a run), released - the run placed; in the other modes, a click.
func trigger(on: bool) -> void:
	if on == _held:
		return
	_held = on
	if mode != "place":
		if on:
			click_mode()
		return
	if on:
		if not aim_pc.is_empty():
			_drag_from = aim_pc.duplicate(true)
			_drag_st = aim_st
			_drag_frame = aim_frame   # (a new structure's: kept while you drag - its grid)
			_run = []
	else:
		if not _run.is_empty():
			place_run()
		elif not _drag_from.is_empty():
			place(aim_st, aim_pc)
		_drag_from = {}
		_drag_st = null
		_clear_run()


## Places `pc` on `st` (null: a new structure at aim_frame) - its cost taken. True if it went.
func place(st: CosmosStructure, pc: Dictionary, quiet := false) -> bool:
	if pc.is_empty():
		return false
	pc = pc.duplicate(true)
	pc["m"] = int(pc.get("m", tier))
	pc["s"] = str(pc.get("s", style))
	pc["c"] = int(pc.get("c", paint))
	var r := why(st, pc)
	if r != "":
		if not quiet:
			_say(r)
		return false
	if st == null:
		var rec := {"o": BuildKit.arr(aim_frame.origin), "x": BuildKit.arr(aim_frame.basis.x), "pieces": []}
		records(pid_of(planet)).append(rec)
		st = _raise(rec)
		st.plan.check(pc)   # (its depth into the ground)
	spend(BuildKit.cost(str(pc["t"]), int(pc["m"])))
	pc["at"] = Time.get_unix_time_from_system()
	pc["own"] = "you"   # (who can lock and unlock it)
	if BuildKit.info(str(pc["t"])).get("use", "") == "chest":
		pc["inv"] = {}
	st.plan.add(pc)
	st.extent()
	st.mark(pc)
	st.poke()
	var I := BuildKit.info(str(pc["t"]))
	if I.get("found", false) or I["kind"] == "free" or str(pc["t"]) == "steps":
		st.clear_ground()
	placed += 1
	_pick_cache = [-1, null, 0]
	if cosmos.has_method("note_event"):
		cosmos.note_event("built")
	Sfx.play("skill/land", -9.0, 0.12)   # (a block set down)
	return true


## A drag's run: from where it began to where you aim now - a wall's (or
## fence's) length along its edge, a floor's (foundation's) rectangle - each
## piece checked as if the run's earlier ones were there.
func _update_run(pc: Dictionary) -> void:
	var a := BuildKit.vec(_drag_from["p"])
	var b := BuildKit.vec(pc["p"])
	var I := BuildKit.info(piece)
	var want := []
	var r0 := int(_drag_from.get("r", 0))
	var bs := BuildKit.turn(r0)
	var l := bs.inverse() * (b - a)
	if I["kind"] == "edge" and absf(l.y) < 0.1:
		var n := roundi(l.x / BuildKit.CELL)
		for k in range(0, n + (1 if n >= 0 else -1), 1 if n >= 0 else -1):
			want.append(a + bs * Vector3(k * BuildKit.CELL, 0, 0))
	elif I["kind"] == "plate" and str(I["shape"]) == "sq" and absf(l.y) < 0.1:
		var nx := clampi(roundi(l.x / BuildKit.CELL), -8, 8)
		var nz := clampi(roundi(l.z / BuildKit.CELL), -8, 8)
		for i in range(0, nx + (1 if nx >= 0 else -1), 1 if nx >= 0 else -1):
			for j in range(0, nz + (1 if nz >= 0 else -1), 1 if nz >= 0 else -1):
				want.append(a + bs * Vector3(i * BuildKit.CELL, 0, j * BuildKit.CELL))
	if want.size() <= 1:
		_clear_run()
		return
	want = want.slice(0, 32)
	# (checked on a copy of the plan, each as if the ones before were built)
	var tmp := BuildPlan.new(_drag_st.plan.pieces.duplicate(true) if _drag_st else [])
	tmp.ground = _drag_st.plan.ground if _drag_st else func(x: float, z: float) -> float: return _ground_in(_drag_frame, x, z)
	var total := {}
	_run = []
	for at: Vector3 in want:
		var q := _drag_from.duplicate(true)
		q["p"] = BuildKit.arr(at)
		var ok := tmp.check(q) == "" and (BuildKit.free_build or not planet.shape.cleared(((_drag_st.transform if _drag_st else aim_frame) * at).normalized()))   # (towns no bar to free building - as for one piece, why())
		if ok:
			var c := BuildKit.cost(piece, tier)
			for k in c:
				total[k] = int(total.get(k, 0)) + int(c[k])
			for k in total:
				if have(k) < int(total[k]) and not BuildKit.free_build:
					ok = false
			if ok:
				tmp.add(q)
		_run.append([q, ok])
	_show_run()


func _show_run() -> void:
	while _ghosts.size() < _run.size():
		var g := MeshInstance3D.new()
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		_ghosts.append(g)
	var fr: Transform3D = _drag_st.global_transform if _drag_st else planet.global_transform * aim_frame
	for i in _ghosts.size():
		var g: MeshInstance3D = _ghosts[i]
		if i >= _run.size():
			g.visible = false
			continue
		var q: Dictionary = _run[i][0]
		g.mesh = ghost_mesh(q)
		g.material_override = BuildKit.ghost_material("ok" if _run[i][1] else "bad")
		g.global_transform = fr * Transform3D(BuildKit.turn(int(q.get("r", 0))), BuildKit.vec(q["p"]))
		g.set_meta("on", planet.global_transform.affine_inverse() * g.global_transform)
		g.visible = true
	_ghost.visible = false


## (Every frame) The previews kept on their world: the aim's looked at 30 times a
## second, but the planet moves every frame (its orbit, the floating origin) - a
## preview left where it was put drifts off and jumps back (a flicker).
func _ride() -> void:
	var pt := planet.global_transform
	for g: MeshInstance3D in [_ghost] + _ghosts:
		if g.visible and g.has_meta("on"):
			g.global_transform = pt * (g.get_meta("on") as Transform3D)


func _clear_run() -> void:
	_run = []
	for g in _ghosts:
		(g as Node).queue_free()
	_ghosts = []


func place_run() -> int:
	var n := 0
	var st := _drag_st
	for it in _run:
		if not it[1]:
			continue
		if place(st, it[0], true):
			n += 1
			if st == null and not structures.is_empty():
				st = structures[-1]
	if n > 0:
		cosmos.hud.flash("%d placed" % n, 2.0)
	return n


## A click in the other modes: the aimed piece taken down, upgraded or painted.
func click_mode() -> void:
	if aim_pc.is_empty() or aim_st == null:
		return
	if not aim_ok:
		_say(aim_why)
		return
	match mode:
		"remove": demolish(aim_st, aim_pc)
		"upgrade": upgrade(aim_st, aim_pc)
		"paint": recolour(aim_st, aim_pc, paint)


## Takes piece `pc` down (and whatever it alone held up): its refund, a chest's things back in your hold.
func demolish(st: CosmosStructure, pc: Dictionary) -> int:
	var i := st.plan.pieces.find(pc)
	if i < 0:
		return 0
	var back := BuildKit.refund(pc, Time.get_unix_time_from_system())
	var gone := st.plan.remove(i)
	for g: Dictionary in gone:
		st.mark(g)
		for k in g.get("inv", {}):
			CosmosGame.data.add_item(k, int(g["inv"][k]))
	give(back)
	st.extent()
	st.poke()
	st.clear_ground()
	_pick_cache = [-1, null, 0]
	var msg := "%s taken down - %s back" % [BuildKit.title(str(pc["t"])), BuildKit.cost_text(back) if not back.is_empty() else "nothing"]
	if gone.size() > 1:
		msg += "; %d more fell with it" % (gone.size() - 1)
	cosmos.hud.flash(msg, 3.0)
	if st.plan.pieces.is_empty():
		records(pid_of(planet)).erase(st.rec)
		structures.erase(st)
		st.queue_free()
	return gone.size()


func upgrade(st: CosmosStructure, pc: Dictionary) -> bool:
	var m := int(pc.get("m", 1))
	if m >= BuildKit.TIERS.size() - 1:
		return false
	var c := upgrade_cost(pc)
	for k in c:
		if have(k) < int(c[k]) and not BuildKit.free_build:
			_say("Needs %s" % BuildKit.cost_text(c))
			return false
	spend(c)
	Sfx.play("space/repair", -6.0)
	pc["m"] = m + 1
	pc.erase("hp")   # (made new in the better material: whole again)
	st.plan.reindex()
	st.mark(pc)
	st.poke()
	_pick_cache = [-1, null, 0]
	cosmos.hud.flash("Now %s" % BuildKit.title(str(pc["t"]), m + 1), 2.0)
	return true


func recolour(st: CosmosStructure, pc: Dictionary, c: int) -> void:
	pc["c"] = c
	st.mark(pc)
	st.poke()


# --- Materials -----------------------------------------------------------------------

## How many of `id` you have: carried and in the hold.
static func have(id: String) -> int:
	var d: Node = CosmosGame.data
	return int(d.carried.get(id, 0)) + d.count(id)


## Takes `c` ({item: n}): what you carry first, then the hold.
static func spend(c: Dictionary) -> void:
	if BuildKit.free_build:
		return
	var d: Node = CosmosGame.data
	for k in c:
		var n := int(c[k])
		n -= Inventory.take(d.carried, k, n)
		if n > 0:
			d.remove_item(k, mini(n, d.count(k)))
	d.changed.emit()


static func give(c: Dictionary) -> void:
	for k in c:
		CosmosGame.data.add_item(k, int(c[k]))


func _say(t: String) -> void:
	if cosmos and cosmos.hud:
		cosmos.hud.flash(t, 2.5)


# --- Cycling the builder's choices ------------------------------------------------------

func turn_piece() -> void:
	turned = posmod(turned + 1, 12)
	_t = 0.0


func next_mode() -> void:
	mode = MODES[(MODES.find(mode) + 1) % MODES.size()]
	_say(MODE_NAMES[mode])
	_t = 0.0


func toggle_snap() -> void:
	snap_on = not snap_on
	_say("Snapping on" if snap_on else "Snapping off - placed where you aim")
	_t = 0.0


func choose(id: String) -> void:
	if BuildKit.PIECES.has(id):
		piece = id
		mode = "place"
		_t = 0.0


# --- Using what's built -----------------------------------------------------------------

## What a click does by you (Cosmos.terminal_here): [label, "build:<kind>:<n>:<key>"] or [].
func prompt(w: Node3D) -> Array:
	if tool_out():   # (the builder in hand: a click builds)
		return []
	var best := []
	var bd := 2.4
	for si in structures.size():
		var st: CosmosStructure = structures[si]
		var l := st.to_local(w.global_position)
		if not st.near(l):
			continue
		for mv in st.movers:
			var at: Vector3 = (mv["xf"] as Transform3D).origin
			var pc := st.piece_of(str(mv["piece"]))
			if pc.is_empty():
				continue
			var bx: AABB = mv["box"]
			var mid: Vector3 = (mv["xf"] as Transform3D) * (bx.get_center() if bx.size != Vector3.ZERO else Vector3(0.35, 0.5, 0.0))
			var dd := Vector2(l.x - mid.x, l.z - mid.z).length()
			if l.y > at.y - 3.4 and l.y < at.y + 1.0 and dd < bd:
				bd = dd
				if bool(pc.get("lk", false)):
					best = ["Locked - Y unlocks it", "build:locked:%d:%s" % [si, str(mv["piece"])]]
				else:
					best = [_door_label(pc), "build:toggle:%d:%s" % [si, str(mv["piece"])]]
		for u in st.uses:
			var at: Vector3 = u[1]
			var dd := Vector2(l.x - at.x, l.z - at.z).length()
			if absf(l.y - at.y) < 1.2 and dd < minf(bd, 1.5):
				bd = dd
				var label: String = {"chest": "Open the chest", "bed": "Rest (and wake here)", "fabricator": "Use the workbench (fabricator)", "refinery": "Use the kiln (refinery)"}.get(u[0], "Use")
				best = [label, "build:%s:%d:%s" % [u[0], si, str(u[2])]]
	return best


static func _door_label(pc: Dictionary) -> String:
	var open := bool(pc.get("o", false))
	match str(pc["t"]):
		"window": return "Open the shutters" if open else "Close the shutters"
		"gate": return "Close the gate" if open else "Open the gate"
		"hatch": return "Close the hatch" if open else "Open the hatch"
		"fence_gate": return "Close the gate" if open else "Open the gate"
	return "Close the door" if open else "Open the door"


## Does it (from Cosmos.use_terminal).
func use(id: String) -> void:
	var parts := id.split(":", true, 3)
	if parts.size() < 4:
		return
	var si := int(parts[2])
	if si < 0 or si >= structures.size():
		return
	var st: CosmosStructure = structures[si]
	var pc := st.piece_of(parts[3])
	if pc.is_empty():
		return
	match parts[1]:
		"toggle":
			st.toggle(pc)
		"locked":
			_say("Locked")
		"chest":
			if cosmos.has_method("open_chest"):
				cosmos.open_chest(pc)
		"bed":
			var w: Node = cosmos.walker
			w.hp = CosmosWalker.MAX_HP
			CosmosGame.data.stamina = Stamina.MAX
			CosmosGame.extra["bed"] = {"planet": pid_of(planet), "at": BuildKit.arr(st.transform * BuildKit.vec(pc["p"]) + st.transform.basis.x * 0.95)}
			cosmos.hud.flash("Rested - health and stamina back; you'll wake here", 3.0)
		"fabricator", "refinery":
			cosmos.open_device(parts[1])


## Y by a door, gate or hatch you built: locked (shut, if it was open) or unlocked.
## Locked, it won't open - for you until you unlock it, for anyone else ever (the
## animals and raiders that come after you push an unlocked one open).
func lock_near(w: Node3D) -> bool:
	var best: Dictionary = {}
	var bst: CosmosStructure = null
	var bd := 2.6
	for st: CosmosStructure in structures:
		var l := st.to_local(w.global_position)
		if not st.near(l):
			continue
		for mv in st.movers:
			var pc := st.piece_of(str(mv["piece"]))
			if pc.is_empty() or not BuildKit.lockable(str(pc["t"])):
				continue
			var at: Vector3 = (mv["xf"] as Transform3D).origin
			var dd := Vector2(l.x - at.x, l.z - at.z).length()
			if dd < bd and l.y > at.y - 3.4 and l.y < at.y + 1.0:
				bd = dd
				best = pc
				bst = st
	if best.is_empty():
		return false
	if str(best.get("own", "you")) != "you":
		_say("Not yours to lock")
		return true
	best["lk"] = not bool(best.get("lk", false))
	if best["lk"] and bool(best.get("o", false)):
		bst.toggle(best)   # (shut first)
	var what := str(BuildKit.info(str(best["t"]))["name"]).to_lower()
	_say(("The %s locked" if best["lk"] else "The %s unlocked") % what)
	return true


## Pushes a body of someone else (an animal, a raider - global `at` its feet,
## radius `r`) out of what's built - a shut door stops it; `opener`: it opens a
## shut door it walks into (not a locked one).
func push_body(at: Vector3, r: float, opener := false) -> Vector3:
	var out := Vector3.ZERO
	for st: CosmosStructure in structures:
		var l := st.to_local(at)
		if not st.near(l) or not st.is_built():
			continue
		if opener:
			for mv in st.movers:
				if mv.get("walk", false) or float(mv["cur"]) > 0.15:
					continue
				var pr = st._leaf_block(mv)
				if pr and pr.depth(l.x, l.z) > -(r + 0.25) and absf(l.y - pr.y0) < 1.5:
					var pc := st.piece_of(str(mv["piece"]))
					if not pc.is_empty() and not bool(pc.get("lk", false)) and not bool(pc.get("o", false)):
						st.toggle(pc)
		out += st.global_basis * st.push(l, r)
	return out


# --- Wear and breaking ---------------------------------------------------------------------

## A bolt's flight from `a` along `dir`, `L` long (global): the first built
## block it meets stops it, and the piece there takes `dmg`. True if one did.
func bolt_hit(a: Vector3, dir: Vector3, L: float, dmg: float) -> bool:
	for st: CosmosStructure in structures:
		if not is_instance_valid(st) or not st.is_built():
			continue
		var lo := st.to_local(a)
		if not st.near(lo, L):
			continue
		var ld := st.global_basis.inverse() * dir
		var h: Array = st.ray_hit(lo, ld, L)
		if float(h[0]) < L:
			var pk: Array = st.plan.pick(lo, ld, float(h[0]) + 0.6)
			if int(pk[0]) >= 0:
				damage(st, int(pk[0]), dmg)
			return true
	return false


## Something hitting what's built round global `at` (within `r`: the terrain
## digger's carve): the nearest piece takes `dmg`. True if one was there.
func damage_at(at: Vector3, r: float, dmg: float) -> bool:
	for st: CosmosStructure in structures:
		var l := st.to_local(at)
		if not st.near(l, r):
			continue
		var bi := -1
		var bdist := r
		for i in st.plan.pieces.size():
			var box := st.plan.pick_box(i)
			var q: Vector3 = BuildKit.turn(int(st.plan.pieces[i].get("r", 0))).inverse() * (l - (box[0] as Vector3))
			var he: Vector3 = box[1]
			var dd := (q - q.clamp(-he, he)).length()
			if dd < bdist:
				bdist = dd
				bi = i
		if bi >= 0:
			damage(st, bi, dmg)
			return true
	return false


## Piece `i` of `st` worn by `dmg` of its toughness: past a quarter's mark, it
## shows (its chunk built again, its look worse); at nothing left, it breaks -
## and whatever only it held up comes down with it.
func damage(st: CosmosStructure, i: int, dmg: float) -> void:
	var pc: Dictionary = st.plan.pieces[i]
	var before := BuildKit.wear_level(pc)
	pc["hp"] = snappedf(maxf(0.0, BuildKit.hp_now(pc) - dmg), 0.1)
	if float(pc["hp"]) <= 0.0:
		var gone := st.plan.remove(i)
		for g: Dictionary in gone:
			st.mark(g)
			for k in g.get("inv", {}):
				CosmosGame.data.add_item(k, int(g["inv"][k]))
		st.extent()
		st.poke()
		st.clear_ground()
		_pick_cache = [-1, null, 0]
		var msg := "%s broke" % BuildKit.title(str(pc["t"]), int(pc.get("m", 1)))
		if gone.size() > 1:
			msg += " - %d more came down with it" % (gone.size() - 1)
		_say(msg)
		Sfx.play("skill/land", -2.0, 0.2)
		if st.plan.pieces.is_empty():
			records(pid_of(planet)).erase(st.rec)
			structures.erase(st)
			st.queue_free()
	elif BuildKit.wear_level(pc) != before:
		st.mark(pc)
		st.poke()


## Where you wake when downed on world `pl` (planet-local), if you've a bed there - else null.
static func bed_on(pl: CosmosPlanet):
	var b: Dictionary = CosmosGame.extra.get("bed", {})
	if b.is_empty() or str(b.get("planet", "")) != pid_of(pl):
		return null
	return BuildKit.vec(b["at"])


# --- The walker, the ship and the lights --------------------------------------------------

## The highest floor of what's built under planet-local `local` (not above its
## feet + a step): metres above the radius, or -INF.
func floor_at(pl: CosmosPlanet, local: Vector3) -> float:
	if pl != planet:
		return -INF
	var best := -INF
	for st: CosmosStructure in structures:
		var tl := st.transform.affine_inverse() * local
		if not st.near(tl) or not st.is_built():
			continue
		var top := st.floor_top(tl)
		if top > -INF:
			best = maxf(best, (st.transform * Vector3(tl.x, top, tl.z)).length() - pl.radius)
	return best


func push_walker(w: CosmosWalker) -> void:
	if w.planet != planet:
		return
	for st: CosmosStructure in structures:
		var l := st.to_local(w.global_position)
		if st.near(l) and st.is_built():
			w.global_position += st.global_basis * st.push(l, CosmosWalker.BODY_R)


func indoors(p: Vector3) -> bool:
	for st: CosmosStructure in structures:
		var l := st.to_local(p)
		if st.near(l) and st.indoors(l):
			return true
	return false


## How far to move a ball (global `p`, radius `r`) out of what's built (your ship, low over it).
func push_ball(p: Vector3, r: float) -> Vector3:
	var out := Vector3.ZERO
	for st: CosmosStructure in structures:
		var l := st.to_local(p)
		if st.near(l, r):
			out += st.global_basis * st.push_ball(l, r)
	return out


## The braziers', wall lamps' and kilns' light: the nearest LIGHTS of them lit (no shadows).
func _lights() -> void:
	var w: Node3D = cosmos.get("walker")
	var f: Vector3 = w.global_position if w else (cosmos.focus().global_position if cosmos.has_method("focus") else Vector3.ZERO)
	var all := []
	for st: CosmosStructure in structures:
		if not is_instance_valid(st) or not st.near(st.to_local(f), 60.0):
			continue
		for l: Vector3 in st.lights:
			var g := st.to_global(l)
			all.append([g.distance_squared_to(f), g])
	all.sort_custom(func(a, b): return a[0] < b[0])
	while _lamps.size() < mini(all.size(), LIGHTS):
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.7, 0.42)
		o.light_energy = 1.5
		o.omni_range = 7.5
		o.omni_attenuation = 1.2
		o.shadow_enabled = false
		add_child(o)
		_lamps.append(o)
	for i in _lamps.size():
		var o: OmniLight3D = _lamps[i]
		o.visible = i < all.size()
		if o.visible:
			o.global_position = all[i][1]
