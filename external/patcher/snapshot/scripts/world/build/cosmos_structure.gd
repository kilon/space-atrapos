class_name CosmosStructure
extends CosmosSolids
## A structure built on a world (CosmosBuilds): its pieces (BuildPlan) in its
## own frame on the planet (a tangent plane at its first foundation, x the way
## you faced), drawn as one merged mesh a CHUNK x CHUNK m square of it (a
## surface a style: the building shader in that empire's palette) - each
## chunk rebuilt on a worker when a piece in it changes, the rest untouched;
## solid as CosmosSolids' blocks (walls, floors, stairs, roofs' slopes), its
## doors, shutters, gates and hatches hinged leaves that swing (a closed
## door's leaf solid). Its record is the save's (CosmosGame.extra
## "structures"): {o: its origin, x: its x axis (planet-local), pieces}.

const CHUNK := 16.0
const SWING := 3.2              # 1/s: a door's swing

var rec := {}
var plan: BuildPlan
var planet: CosmosPlanet
var built := false              # (every chunk in at least once)
var _chunks := {}               # Vector2i -> {node, solids, movers, lights, uses}
var _dirty := {}                # Vector2i -> true
var _task := -1
var _job := {}
var movers: Array = []          # [{node, piece (record), xf, axis, angle, cur, box}]
var lights: Array = []          # [frame position]
var uses: Array = []            # [kind, frame position, piece record]
var _swinging := false


## The frame on its planet (planet-local) of record `r`.
static func frame_of(r: Dictionary) -> Transform3D:
	var o := BuildKit.vec(r["o"])
	var up := o.normalized()
	var x := BuildKit.vec(r["x"])
	x = (x - up * x.dot(up)).normalized()
	return Transform3D(Basis(x, up, x.cross(up)), o)


func setup(pl: CosmosPlanet, r: Dictionary) -> void:
	planet = pl
	rec = r
	name = "Structure"
	ground = -INF
	if not rec.has("pieces"):
		rec["pieces"] = []
	plan = BuildPlan.new(rec["pieces"])
	plan.ground = ground_y
	add_to_group("cam_solid")
	extent()
	mark_all()
	clear_ground()


## The ground's height in its frame under (x, z) - for its foundations.
func ground_y(x: float, z: float) -> float:
	if planet == null:
		return -0.4
	var xf := frame_of(rec)
	var q := xf * Vector3(x, 0.0, z)
	var d := q.normalized()
	var hgt: float = planet.shape.floor_below(q) if planet.shape.carved_near(q) else planet.shape.height(d)
	return (planet.radius + hgt) - q.length()


## The ground under its foundations (and what stands on the ground itself) bare:
## no plants or boulders there (PlanetShape.set_bare) - the patches near built again.
func clear_ground() -> void:
	if planet == null:
		return
	var xf := frame_of(rec)
	var dirs := PackedVector3Array()
	var coss := PackedFloat32Array()
	for pc in plan.pieces:
		var I := BuildKit.info(str(pc["t"]))
		var p := BuildKit.vec(pc["p"])
		var r := 0.0
		if I.get("found", false):
			r = {"sq": 3.0, "tri": 2.3, "half": 2.4, "quarter": 1.5}.get(str(I["shape"]), 3.0)
		elif str(pc["t"]) == "steps":
			r = 2.0
		elif I["kind"] == "free" and plan.plate_under(p) < 0:
			r = 1.0
		if r > 0.0:
			dirs.append((xf * p).normalized())
			coss.append(cos(r / planet.radius))
	var owner := "st:" + BuildKit.key(xf.origin)
	planet.shape.set_bare(owner, dirs, coss)
	planet._rebuild_near(xf * bounds.get_center(), bounds.size.length() * 0.5 + 4.0)


static func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))


## Its pieces' reach in its frame (grown by `m`): what's worth asking it about.
var bounds := AABB()


func extent() -> void:
	var first := true
	for pc in plan.pieces:
		var p := BuildKit.vec(pc["p"])
		if first:
			bounds = AABB(p, Vector3.ZERO)
			first = false
		else:
			bounds = bounds.expand(p)
	bounds = bounds.grow(6.0)
	set_meta("cam_reach", maxf(bounds.position.length(), bounds.end.length()) + 10.0)


func near(local: Vector3, m := 0.0) -> bool:
	return bounds.grow(m).has_point(local)


func mark_all() -> void:
	for pc in plan.pieces:
		_dirty[chunk_of(BuildKit.vec(pc["p"]))] = true
	for k in _chunks:
		_dirty[k] = true


## Piece `pc` changed: its chunk (and its neighbours' - posts at a chunk's edge) built again.
func mark(pc: Dictionary) -> void:
	var c := chunk_of(BuildKit.vec(pc["p"]))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var k := c + Vector2i(dx, dz)
			if _chunks.has(k) or k == c:
				_dirty[k] = true


func busy() -> bool:
	return _task >= 0 or not _dirty.is_empty()


func _process(_delta: float) -> void:
	if _task >= 0:
		if not Jobs.done(_task):
			return
		Jobs.wait(_task)
		_task = -1
		_take(_job)
		_job = {}
	if not _dirty.is_empty():
		_start()
	if _swinging:
		_swing(_delta)
	elif _task < 0 and _dirty.is_empty():
		set_process(false)


func poke() -> void:
	set_process(true)


## The dirty chunks' pieces (and posts) to a worker: their meshes, solids, leaves.
func _start() -> void:
	var want := _dirty.keys()
	_dirty = {}
	var by := {}
	for k in want:
		by[k] = []
	for pc in plan.pieces:
		var k := chunk_of(BuildKit.vec(pc["p"]))
		if by.has(k):
			by[k].append(pc.duplicate(true))
	var posts := {}
	for k in want:
		posts[k] = []
	for pt in plan.posts():
		var k := chunk_of(pt[0])
		if posts.has(k):
			posts[k].append(pt)
	var keep := []   # (the solids of the chunks not rebuilt: for the grid)
	for k in _chunks:
		if not by.has(k):
			keep.append_array(_chunks[k]["solids"])
	var job := {"by": by, "posts": posts, "keep": keep}
	_job = job
	_task = Jobs.add(func(): _build(job), false, "structure")


static func _build(job: Dictionary) -> void:
	var out := {}
	var all: Array = (job["keep"] as Array).duplicate()
	for k in job["by"]:
		var builders := {}   # style -> Builder
		var res := {"solids": [], "movers": [], "lights": [], "uses": []}
		for pc: Dictionary in job["by"][k]:
			var s := str(pc.get("s", "minoa"))
			if not builders.has(s):
				builders[s] = CosmosTown.Builder.new()
			var r := BuildKit.emit(builders[s], pc)
			res["solids"].append_array(r["solids"])
			for mv: Dictionary in r["movers"]:
				mv["piece"] = BuildKit.key(BuildKit.vec(pc["p"])) + "|" + str(pc["t"]) + "|%d" % int(pc.get("r", 0))
				res["movers"].append(mv)
			res["lights"].append_array(r["lights"])
			for u in r["uses"]:
				res["uses"].append([u[0], u[1], BuildKit.key(BuildKit.vec(pc["p"])) + "|" + str(pc["t"])])
		for pt in job["posts"][k]:
			var s := str(pt[3])
			if not builders.has(s):
				builders[s] = CosmosTown.Builder.new()
			var lb := CosmosTown.Builder.new()
			lb.rng.seed = hash(BuildKit.key(pt[0]))
			var ps := BuildKit.post(lb, Vector3(0, (pt[0] as Vector3).y, 0), float(pt[1]), int(pt[2]), s)
			BuildKit.merge(builders[s], lb, int(pt[4]), pt[0])
			for so in ps:
				res["solids"].append(BuildKit.place_solid(so, int(pt[4]), pt[0]))
		var meshes := {}
		for s in builders:
			var b: CosmosTown.Builder = builders[s]
			if b.verts.size() > 0:
				meshes[s] = b.mesh()
		res["meshes"] = meshes
		res["solids"] = CosmosSolids.merge_boxes(res["solids"], 0.05)
		out[k] = res
		all.append_array(res["solids"])
	job["out"] = out
	job["all"] = all
	job["grid"] = CosmosSolids.grid_of(all)


## A worker's chunks in: their meshes swapped, leaves hung, the solids' grid.
func _take(job: Dictionary) -> void:
	if not job.has("out"):
		return
	for k in job["out"]:
		var res: Dictionary = job["out"][k]
		var old: Dictionary = _chunks.get(k, {})
		if old.get("node") != null:
			(old["node"] as Node3D).visible = false
			(old["node"] as Node).queue_free()
		for mv in old.get("movers", []):
			if is_instance_valid(mv["node"]):
				(mv["node"] as Node).queue_free()
		var meshes: Dictionary = res["meshes"]
		var node: Node3D = null
		if not meshes.is_empty():
			node = Node3D.new()
			node.name = "Chunk_%d_%d" % [k.x, k.y]
			for s in meshes:
				var mi := MeshInstance3D.new()
				mi.mesh = meshes[s]
				mi.material_override = BuildKit.material(s)
				mi.visibility_range_end = 3000.0
				node.add_child(mi)
			add_child(node)
		var mvs := []
		for mv: Dictionary in res["movers"]:
			var mi := MeshInstance3D.new()
			mi.mesh = (mv["lb"] as CosmosTown.Builder).mesh()   # (made here: a leaf's few faces - meshes aren't made on the workers)
			mi.material_override = BuildKit.material(_style_of(str(mv["piece"])))
			mi.visibility_range_end = 400.0
			add_child(mi)
			mv["node"] = mi
			var open := _is_open(str(mv["piece"]))
			mv["cur"] = 1.0 if open else 0.0
			mv["want"] = mv["cur"]
			_pose(mv)
			mvs.append(mv)
		if node == null and mvs.is_empty() and res["solids"].is_empty():
			_chunks.erase(k)
		else:
			_chunks[k] = {"node": node, "solids": res["solids"], "movers": mvs, "lights": res["lights"], "uses": res["uses"]}
	_solids = job["all"]
	_grid = job["grid"]
	movers = []
	lights = []
	uses = []
	for k in _chunks:
		movers.append_array(_chunks[k]["movers"])
		lights.append_array(_chunks[k]["lights"])
		uses.append_array(_chunks[k]["uses"])
	if _dirty.is_empty():
		built = true


func _style_of(mkey: String) -> String:
	var pc := piece_of(mkey)
	return str(pc.get("s", "minoa")) if not pc.is_empty() else "minoa"


## The record a mover's or use's key names ("<anchor key>|<id>[|<turn>]"), or {}.
func piece_of(mkey: String) -> Dictionary:
	var parts := mkey.split("|")
	for pc in plan.pieces:
		if str(pc["t"]) == parts[1] and BuildKit.key(BuildKit.vec(pc["p"])) == parts[0] and (parts.size() < 3 or int(pc.get("r", 0)) == int(parts[2])):
			return pc
	return {}


func _is_open(mkey: String) -> bool:
	var pc := piece_of(mkey)
	if pc.is_empty():
		return false
	return bool(pc.get("o", false))


func _pose(mv: Dictionary) -> void:
	var a := float(mv["angle"]) * (1.0 - float(mv["cur"]) if mv.get("open0", false) else float(mv["cur"]))
	(mv["node"] as Node3D).transform = (mv["xf"] as Transform3D) * Transform3D(Basis(mv["axis"], a), Vector3.ZERO)


## Opens or shuts piece `pc`'s leaves (its record's `o`).
func toggle(pc: Dictionary) -> bool:
	pc["o"] = not bool(pc.get("o", false))
	var k := BuildKit.key(BuildKit.vec(pc["p"])) + "|" + str(pc["t"]) + "|%d" % int(pc.get("r", 0))
	for mv in movers:
		if mv["piece"] == k:
			mv["want"] = 1.0 if pc["o"] else 0.0
	_swinging = true
	set_process(true)
	return bool(pc["o"])


func _swing(delta: float) -> void:
	var any := false
	for mv in movers:
		if not is_instance_valid(mv["node"]):
			continue
		if float(mv["cur"]) != float(mv["want"]):
			mv["cur"] = move_toward(float(mv["cur"]), float(mv["want"]), SWING * delta * 0.6)
			_pose(mv)
			any = true
	_swinging = any


## A closed leaf that blocks (a door, a gate): its block in the frame, or null.
func _leaf_block(mv: Dictionary):
	var box: AABB = mv["box"]
	if box.size == Vector3.ZERO or float(mv["cur"]) > 0.15:
		return null
	var xf: Transform3D = mv["xf"]
	var poly := PackedVector2Array()
	for q in [Vector3(box.position.x, 0, box.position.z), Vector3(box.end.x, 0, box.position.z), Vector3(box.end.x, 0, box.end.z), Vector3(box.position.x, 0, box.end.z)]:
		var w: Vector3 = xf * q
		poly.append(Vector2(w.x, w.z))
	var y0 := (xf * box.position).y
	return CosmosSolids.Prism.new(poly, minf(y0, (xf * box.end).y), maxf(y0, (xf * box.end).y))


func floor_top(p: Vector3) -> float:
	var best := super.floor_top(p)
	for mv in movers:
		if mv.get("walk", false):   # (a hatch's lid, shut: walked on)
			var pr = _leaf_block(mv)
			if pr and pr.has(p.x, p.z) and pr.y1 <= p.y + STEP and pr.y1 > best:
				best = pr.y1
	return best


func push(p: Vector3, r: float) -> Vector3:
	var out := super.push(p, r)
	for mv in movers:
		if mv.get("walk", false):
			continue
		var pr = _leaf_block(mv)
		if pr and (mv["xf"] as Transform3D).origin.distance_to(p) < 4.0:
			out += _push_prism(pr, p + out, r, p.y)
	return out


func is_built() -> bool:
	return not _solids.is_empty()


func _exit_tree() -> void:
	if _task >= 0:
		Jobs.wait(_task)
		_task = -1
