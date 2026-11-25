class_name SolidsEdit
extends RefCounted
## One way to read and edit what's solid, whatever kind of place holds it (the
## Live Editor's Collision tab, its tests). The game's collision is its own
## geometry, no physics bodies, kept by each kind of place in its own form:
##   CosmosSolids (a town, a structure of yours) - AABBs and Prisms in a grid;
##   CosmosDungeon - AABBs in a grid;
##   CosmosStation - oriented boxes and cylinders (_solids: [ring?, centre, bound, inverse, half, cylinder?, basis]);
##   CosmosHangar - the camera's boxes (_boxes) and the feet's footprints (_blocks);
##   CosmosNpcInterior - the furniture's footprints (blocks).
## Here each is a list of shapes in the node's own space:
##   {kind: "box" | "obox" | "cyl" | "prism", xf: Transform3D (its middle, its turn),
##    half: Vector3, on: bool (solid - off: kept, shown, not in the way),
##    use: "" | "cam" | "walk" | "both" (the hangar's: what it stops), ro: bool (a
##    sloped or many-sided prism: deleted or turned off, not moved), src (the prism), id (its index in the base)}.
## Nothing here runs while nobody edits: the systems keep their own arrays and
## lookups; set_boxes rebuilds them once, at the edit.
##
## Persisted (LiveEdits, section "collision"): the edit as a difference from what
## the place builds (`base`) - {path, del: [shape], mod: [[from, to]], add: [shape]}
## (shapes encoded: enc_shape) - put back by matching the shapes it changed, so it
## holds while the place is built the same (its key: the builders' "edit_key").

const SECTION := "collision"
const EPS := 0.03                # m: two shapes the same (matching an edit to what's built)
const WALK_H := 1.2              # m: how high a footprint (the hangar's, an interior's) is drawn


## The kind of collision `n` itself keeps ("" - none).
static func kind_of(n: Object) -> String:
	if n is CosmosSolids:
		return "solids"
	if n is CosmosDungeon:
		return "dungeon"
	if n is CosmosStation:
		return "station"
	if n is CosmosHangar:
		return "hangar"
	if n is CosmosNpcInterior:
		return "interior"
	return ""


## The node holding the solids `n` is part of: itself or its nearest such ancestor (null - none).
static func owner_of(n: Node) -> Node:
	var a := n
	while a:
		if kind_of(a) != "":
			return a
		a = a.get_parent()
	return null


## How its boxes may turn: "none" (axis-aligned), "yaw" (about up), "full".
static func rotation_of(n: Node) -> String:
	match kind_of(n):
		"solids":
			return "yaw"
		"station":
			return "full"
	return "none"


## Its solids are in (built) - nothing to edit before.
static func has_solids(n: Node) -> bool:
	var src = _primary(n)
	return src is Array and not (src as Array).is_empty()


## Its solids are still the ones last read or set here (not built again since).
static func current(n: Node) -> bool:
	return n.has_meta("solids_base") and _same_src(n, _primary(n))


## Its shapes as they are now (edited or as built) - copies, free to change.
static func boxes(n: Node) -> Array:
	base(n)
	return _copy(n.get_meta("solids_now") if n.has_meta("solids_now") else n.get_meta("solids_base", []))


## Its shapes as it built them (read once a build: the edits' reference).
static func base(n: Node) -> Array:
	var src = _primary(n)
	if n.has_meta("solids_base") and _same_src(n, src):
		return n.get_meta("solids_base")
	var b := _read(n)
	for i in b.size():
		b[i]["id"] = i
	n.set_meta("solids_base", b)
	n.remove_meta("solids_now")
	_mark_src(n, src)
	return b


## Replaces its solids with `shapes` (those on) and rebuilds its lookups, at once.
static func set_boxes(n: Node, shapes: Array) -> void:
	base(n)   # (what it built, read before it's replaced)
	var list := _copy(shapes)
	match kind_of(n):
		"solids":
			_set_solids(n, list)
		"dungeon":
			_set_dungeon(n, list)
		"station":
			_set_station(n, list)
		"hangar":
			_set_hangar(n, list)
		"interior":
			_set_interior(n, list)
		_:
			return
	n.set_meta("solids_now", list)
	_mark_src(n, _primary(n))


## Back to what it built.
static func revert(n: Node) -> void:
	if n.has_meta("solids_base"):
		set_boxes(n, n.get_meta("solids_base"))
		n.remove_meta("solids_now")


# --- Edits kept: the difference from what's built ------------------------------------

## Its edit as a record ({} - nothing changed): what was deleted, changed, added.
static func record(n: Node) -> Dictionary:
	var b := base(n)
	var now: Array = n.get_meta("solids_now", b)
	var seen := {}
	var dels: Array = []
	var mods: Array = []
	var adds: Array = []
	for s: Dictionary in now:
		var i := int(s.get("id", -1))
		if i >= 0 and i < b.size() and not seen.has(i):
			seen[i] = true
			if not same(b[i], s):
				mods.append([enc_shape(b[i]), enc_shape(s)])
		else:
			adds.append(enc_shape(s))
	for i in b.size():
		if not seen.has(i):
			dels.append(enc_shape(b[i]))
	if dels.is_empty() and mods.is_empty() and adds.is_empty():
		return {}
	return {"del": dels, "mod": mods, "add": adds}


## Puts a record back on `n` (as built - each change found by the shape it
## changed; one not found is let be): true when it changed something. Again and
## again is the same (always from what it built).
static func apply_record(n: Node, rec: Dictionary) -> bool:
	if kind_of(n) == "" or not has_solids(n):
		return false
	var b := base(n)
	var out: Array = _copy(b)
	var used := {}
	var changed := false
	for e in rec.get("del", []):
		var j := _match(b, dec_shape(e), used)
		if j >= 0:
			used[j] = true
			out[j] = null
			changed = true
	for e in rec.get("mod", []):
		var j := _match(b, dec_shape(e[0]), used)
		if j < 0:
			continue
		used[j] = true
		var to := dec_shape(e[1])
		if bool(b[j].get("ro", false)):   # (a prism: only its being solid changes)
			to = (b[j] as Dictionary).duplicate()
			to["on"] = bool(dec_shape(e[1]).get("on", true))
		to["id"] = j
		out[j] = to
		changed = true
	for e in rec.get("add", []):
		var s := dec_shape(e)
		s["id"] = -1
		out.append(s)
		changed = true
	if not changed:
		return false
	set_boxes(n, out.filter(func(s): return s != null))
	return true


## A place's solids just came in (its builder calls this, a dictionary lookup):
## its kind's kept edit put back on them now, not at the next of LiveEdits' tries.
static func installed(n: Node) -> void:
	if not n.has_meta("edit_key"):
		return
	if not LiveEdits._loaded:
		LiveEdits.load_all()
	var d = LiveEdits.data.get(str(n.get_meta("edit_key")), {})
	if d is Dictionary and (d as Dictionary).get(SECTION) is Dictionary and not (d[SECTION] as Dictionary).is_empty():
		apply_record(n, d[SECTION])


static func _match(b: Array, s: Dictionary, used: Dictionary) -> int:
	for j in b.size():
		if not used.has(j) and same(b[j], s, true):
			return j
	return -1


## Two shapes the same (within EPS). `shape_only`: whether they're solid aside.
static func same(a: Dictionary, b: Dictionary, shape_only := false) -> bool:
	if str(a.get("kind")) != str(b.get("kind")) or str(a.get("use", "")) != str(b.get("use", "")):
		return false
	if not shape_only and bool(a.get("on", true)) != bool(b.get("on", true)):
		return false
	var xa: Transform3D = a["xf"]
	var xb: Transform3D = b["xf"]
	if xa.origin.distance_to(xb.origin) > EPS or (a["half"] as Vector3).distance_to(b["half"]) > EPS:
		return false
	for k in 3:
		if xa.basis[k].distance_to(xb.basis[k]) > 0.01:
			return false
	return true


## A shape for JSON (LiveEdits.enc for its numbers).
static func enc_shape(s: Dictionary) -> Dictionary:
	var xf: Transform3D = s["xf"]
	var d := {"k": str(s["kind"]), "c": LiveEdits.enc(xf.origin), "h": LiveEdits.enc(s["half"]), "on": bool(s.get("on", true))}
	if not xf.basis.is_equal_approx(Basis.IDENTITY):
		d["b"] = LiveEdits.enc(xf.basis)
	if str(s.get("use", "")) != "":
		d["u"] = str(s["use"])
	return d


static func dec_shape(d: Dictionary) -> Dictionary:
	var b: Basis = LiveEdits.dec(d["b"]) if d.has("b") else Basis.IDENTITY
	var c: Vector3 = LiveEdits.dec(d.get("c"))
	var h: Vector3 = LiveEdits.dec(d.get("h"))
	return {"kind": str(d.get("k", "box")), "xf": Transform3D(b, c), "half": h, "on": bool(d.get("on", true)),
		"use": str(d.get("u", "")), "ro": str(d.get("k", "")) == "prism"}


## A plain box (an editor's new one): centre, half size, its turn.
static func make(c: Vector3, half: Vector3, b := Basis.IDENTITY, use := "") -> Dictionary:
	return {"kind": "box", "xf": Transform3D(b, c), "half": half.abs(), "on": true, "use": use, "ro": false, "id": -1}


## A shape's bounds (its own space -> the node's): an AABB.
static func bounds(s: Dictionary) -> AABB:
	var h: Vector3 = s["half"]
	return (s["xf"] as Transform3D) * AABB(-h, h * 2.0)


## Where the ray (node space) first meets the shape (INF: not within `limit`).
static func ray(s: Dictionary, o: Vector3, d: Vector3, limit: float) -> float:
	var inv := (s["xf"] as Transform3D).affine_inverse()
	var h: Vector3 = s["half"]
	var t := CosmosSolids._ray_box(inv * o, inv.basis * d, AABB(-h, h * 2.0), limit)
	return t


## How far `p` (node space) is from the shape (0 inside).
static func distance(s: Dictionary, p: Vector3) -> float:
	var xf: Transform3D = s["xf"]
	var l := xf.affine_inverse() * p
	var h: Vector3 = s["half"]
	return (xf.basis * (l - l.clamp(-h, h))).length()


# --- Each system: its array, read and written ------------------------------------------

## The array a system's solids are installed as (to tell a new build from ours).
static func _primary(n: Node) -> Variant:
	match kind_of(n):
		"solids", "dungeon", "station":
			return n.get("_solids")
		"hangar":
			return n.get("_boxes")
		"interior":
			return n.get("blocks")
	return null


static func _same_src(n: Node, src: Variant) -> bool:
	return n.has_meta("solids_src") and is_same(n.get_meta("solids_src"), src) and src is Array \
		and int(n.get_meta("solids_n", -1)) == (src as Array).size()


static func _mark_src(n: Node, src: Variant) -> void:
	n.set_meta("solids_src", src)
	n.set_meta("solids_n", (src as Array).size() if src is Array else -1)


static func _copy(list: Array) -> Array:
	var out: Array = []
	for s in list:
		out.append((s as Dictionary).duplicate() if s is Dictionary else s)
	return out


static func _read(n: Node) -> Array:
	var out: Array = []
	match kind_of(n):
		"solids", "dungeon":
			for s in n.get("_solids"):
				out.append(_from_block(s))
		"station":
			for s: Array in n.get("_solids"):
				out.append({"kind": "cyl" if s[5] else "obox", "xf": Transform3D(s[6], s[1]), "half": s[4], "on": true,
					"use": "", "ro": bool(s[0]), "ring": bool(s[0])})
		"hangar":
			var feet := {}   # (a footprint the same as a camera box's: one box, both)
			for i in (n.get("_blocks") as Array).size():
				var bl: Array = n.get("_blocks")[i]
				var k := _foot_key(bl[0], bl[1], bl[2], bl[3])
				if not feet.has(k):
					feet[k] = []
				feet[k].append(i)
			var taken := {}
			for bx: Array in n.get("_boxes"):
				var c: Vector3 = bx[0]
				var h: Vector3 = bx[1]
				var k := _foot_key(c.x - h.x, c.z - h.z, c.x + h.x, c.z + h.z)
				var use := "cam"
				for i in feet.get(k, []):
					if not taken.has(i):
						taken[i] = true
						use = "both"
						break
				out.append(make(c, h, Basis.IDENTITY, use))
			for i in (n.get("_blocks") as Array).size():
				if not taken.has(i):
					var bl: Array = n.get("_blocks")[i]
					out.append(_foot(bl, 0.0, "walk"))
		"interior":
			for bl: Array in n.get("blocks"):
				out.append(_foot(bl, float(n.get("sill")), "walk"))
	for s in out:
		s["on"] = true
	return out


static func _foot_key(x0: float, z0: float, x1: float, z1: float) -> String:
	return "%d,%d,%d,%d" % [roundi(x0 * 20.0), roundi(z0 * 20.0), roundi(x1 * 20.0), roundi(z1 * 20.0)]


static func _foot(bl: Array, y0: float, use: String) -> Dictionary:
	var c := Vector3((float(bl[0]) + float(bl[2])) * 0.5, y0 + WALK_H * 0.5, (float(bl[1]) + float(bl[3])) * 0.5)
	return make(c, Vector3((float(bl[2]) - float(bl[0])) * 0.5, WALK_H * 0.5, (float(bl[3]) - float(bl[1])) * 0.5), Basis.IDENTITY, use)


## A CosmosSolids block as a shape: an AABB; a Prism that's a flat-topped
## rectangle, a box turned about up; any other prism, read-only.
static func _from_block(s: Variant) -> Dictionary:
	if s is AABB:
		var b: AABB = s
		return make(b.get_center(), b.size * 0.5)
	var pr: CosmosSolids.Prism = s
	var p := pr.poly
	if pr.planes.is_empty() and p.size() == 4:
		var e0 := p[1] - p[0]
		var e1 := p[2] - p[1]
		var e2 := p[3] - p[2]
		if absf(e0.dot(e1)) < 1e-3 * e0.length() * e1.length() and (e0 + e2).length() < 1e-3:
			var c := (p[0] + p[1] + p[2] + p[3]) * 0.25
			var yaw := atan2(-e0.y, e0.x)
			var sh := make(Vector3(c.x, (pr.y0 + pr.y1) * 0.5, c.y), Vector3(e0.length() * 0.5, (pr.y1 - pr.y0) * 0.5, e1.length() * 0.5),
				Basis(Vector3.UP, yaw))
			return sh
	var a := pr.aabb()
	return {"kind": "prism", "xf": Transform3D(Basis.IDENTITY, a.get_center()), "half": a.size * 0.5, "on": true,
		"use": "", "ro": true, "src": pr}


## A shape as a CosmosSolids block (null - off).
static func _to_block(s: Dictionary, yaw_ok := true) -> Variant:
	if not bool(s.get("on", true)):
		return null
	if str(s["kind"]) == "prism":
		return s.get("src")
	var xf: Transform3D = s["xf"]
	var h: Vector3 = s["half"]
	var bx := xf.basis.orthonormalized()
	if bx.is_equal_approx(Basis.IDENTITY) or not yaw_ok:
		return xf * AABB(-h, h * 2.0)
	var yaw := atan2(-bx.x.z, bx.x.x)
	var r := Basis(Vector3.UP, yaw)
	var c := xf.origin
	var poly := PackedVector2Array()
	for q in [Vector2(-h.x, -h.z), Vector2(h.x, -h.z), Vector2(h.x, h.z), Vector2(-h.x, h.z)]:
		var w := r * Vector3(q.x, 0.0, q.y)
		poly.append(Vector2(c.x + w.x, c.z + w.z))
	return CosmosSolids.Prism.new(poly, c.y - h.y, c.y + h.y)


static func _set_solids(n: Node, list: Array) -> void:
	var solids: Array = []
	for s in list:
		var b = _to_block(s)
		if b != null:
			solids.append(b)
	n.set("_solids", solids)
	n.set("_grid", CosmosSolids.grid_of(solids))


static func _set_dungeon(n: Node, list: Array) -> void:
	var solids: Array = []
	for s in list:
		var b = _to_block(s, false)
		if b != null:
			solids.append(b)
	n.set("_solids", solids)
	n.set("_grid", CosmosSolids.grid_of(solids))   # (its cells: CosmosTown.CELL, the same 8 m)


static func _set_station(n: Node, list: Array) -> void:
	var solids: Array = []
	var bound := 0.0
	for s: Dictionary in list:
		if not bool(s.get("on", true)):
			continue
		var xf: Transform3D = s["xf"]
		var h: Vector3 = s["half"]
		var cyl := str(s["kind"]) == "cyl"
		if cyl:
			h.z = h.x
		solids.append([bool(s.get("ring", false)), xf.origin, h.length(), xf.affine_inverse(), h, cyl, xf.basis])
		bound = maxf(bound, xf.origin.length() + h.length())
	n.set("_solids", solids)
	n.set("_bound", maxf(bound, 1.0))


static func _set_hangar(n: Node, list: Array) -> void:
	var cam: Array = []
	var feet: Array = []
	for s: Dictionary in list:
		if not bool(s.get("on", true)):
			continue
		var bb := bounds(s)
		var use := str(s.get("use", ""))
		if use != "walk":
			cam.append([bb.get_center(), bb.size * 0.5])
		if use != "cam":
			feet.append([bb.position.x, bb.position.z, bb.end.x, bb.end.z])
	n.set("_boxes", cam)
	n.set("_blocks", feet)
	n.set("_cells", {})
	n.set("_cells_n", -1)   # (its cells of blocks made again at the next look)


static func _set_interior(n: Node, list: Array) -> void:
	var feet: Array = []
	for s: Dictionary in list:
		if bool(s.get("on", true)):
			var bb := bounds(s)
			feet.append([bb.position.x, bb.position.z, bb.end.x, bb.end.z])
	n.set("blocks", feet)
